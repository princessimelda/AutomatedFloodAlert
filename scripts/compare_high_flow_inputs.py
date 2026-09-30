"""Compare input groups and alert thresholds without using final test years."""
from pathlib import Path
import json
import hashlib
import numpy as np
import pandas as pd
import joblib
from sklearn.base import clone
from sklearn.metrics import precision_score, recall_score, f1_score, average_precision_score, roc_auc_score
ROOT = Path(__file__).resolve().parents[1]


def compare_inputs():
    source = ROOT / 'data/processed/high_flow_models'
    out = source / 'input_comparison'
    out.mkdir(parents=True, exist_ok=True)
    saved = ROOT / 'models/high_flow_experiment'
    model_dir = saved / 'input_comparison'
    model_dir.mkdir(parents=True, exist_ok=True)
    path = source / 'labelled_research_dataset.csv'
    # Discard final test rows before fitting or scoring anything.
    data = pd.read_csv(path)
    data = data[data.partition.isin(['train', 'validation'])].copy()
    train = data[data.partition == 'train']
    valid = data[data.partition == 'validation']
    assert train.date.max() < valid.date.min() and valid.date.max() == '2021-12-31'
    assert valid.onset.dtype == bool
    meta = json.loads((source / 'experiment_metadata.json').read_text())
    all_features = meta['features']
    groups = {'combined': all_features,
              'flow_only': [f for f in all_features if not f.startswith('rain_prev')],
              'rainfall_only': [f for f in all_features if not f.startswith('flow_')]}
    predictions = []
    for name in ['logistic_regression', 'random_forest', 'xgboost']:
        original = joblib.load(saved / f'{name}.joblib')
        for group, features in groups.items():
            model = original['model'] if group == 'combined' else clone(original['model'])
            if group != 'combined':
                model.fit(train[features], train.high_flow)
            scores = model.predict_proba(valid[features])[:, 1]
            table = valid[['cell_id', 'date', 'high_flow', 'previous_high', 'onset']].copy()
            table['candidate'] = name + '__' + group
            table['score'] = scores
            predictions.append(table)
            joblib.dump({**original, 'model': model, 'features': features}, model_dir / f'{name}__{group}.joblib')
    prediction = pd.concat(predictions, ignore_index=True)
    prediction.to_csv(out / 'validation_scores.csv', index=False)

    def measure(table, threshold):
        y = table.high_flow.to_numpy()
        pred = table.score.to_numpy() >= threshold
        onset = table.onset.to_numpy()
        quiet = table.previous_high.to_numpy() == 0
        return dict(precision=precision_score(y, pred, zero_division=0), recall=recall_score(y, pred, zero_division=0),
                    f1=f1_score(y, pred, zero_division=0),
                    average_precision=average_precision_score(y, table.score) if y.sum() else np.nan,
                    roc_auc=roc_auc_score(y, table.score) if len(np.unique(y)) == 2 else np.nan,
                    false_alarms=int((pred & (y == 0)).sum()), missed_high_days=int((~pred & (y == 1)).sum()),
                    onsets=int(onset.sum()), detected_onsets=int((pred & onset).sum()),
                    onset_recall=float(pred[onset].mean()) if onset.any() else np.nan,
                    onset_alert_precision=float((pred & onset).sum() / max(1, (pred & quiet).sum())), rows=len(table))
    default = []
    sweep = []
    checks = []
    per_cell = []
    for candidate, table in prediction.groupby('candidate'):
        default.append(dict(candidate=candidate, **measure(table, .5)))
        early = table[table.date < '2021-01-01']
        later = table[table.date >= '2021-01-01']
        for threshold in np.round(np.arange(.1, .951, .05), 2):
            sweep.append(dict(candidate=candidate, threshold=float(threshold), **measure(early, threshold)))
        local = pd.DataFrame([r for r in sweep if r['candidate'] == candidate])
        best = local.sort_values(['f1', 'precision', 'threshold'], ascending=[False, False, False]).iloc[0]
        threshold = float(best.threshold)
        for period, subset in [('2019_2020_tuning', early), ('2021_check', later), ('all_validation', table)]:
            checks.append(dict(candidate=candidate, threshold=threshold, period=period, **measure(subset, threshold)))
        for cell, subset in later.groupby('cell_id'):
            per_cell.append(dict(candidate=candidate, cell_id=cell, threshold=threshold, **measure(subset, threshold)))
    default = pd.DataFrame(default)
    sweep = pd.DataFrame(sweep)
    checks = pd.DataFrame(checks)
    default.to_csv(out / 'input_comparison_at_050.csv', index=False)
    sweep.to_csv(out / 'threshold_sweep_2019_2020.csv', index=False)
    checks.to_csv(out / 'selected_threshold_results.csv', index=False)
    pd.DataFrame(per_cell).to_csv(out / '2021_results_by_cell.csv', index=False)
    # Choose on the earlier validation portion, not the 2021 check.
    winner = checks[checks.period == '2019_2020_tuning'].sort_values(['f1', 'precision', 'candidate'], ascending=[False, False, True]).iloc[0]
    bundle = joblib.load(model_dir / f'{winner.candidate}.joblib')
    bundle['decision_threshold'] = float(winner.threshold)
    bundle['selection_rule'] = 'Maximum 2019–2020 daily F1; tie by precision then candidate name'
    bundle['status'] = 'Provisional retrospective candidate; final test not evaluated'
    joblib.dump(bundle, model_dir / 'provisional_selected.joblib')
    # Add persistence on the same later-year check for a fair comparison.
    persistence = valid[valid.date >= '2021-01-01'].copy()
    persistence['score'] = persistence.previous_high
    baseline = measure(persistence, .5)
    baseline['roc_auc'] = None
    baseline['average_precision'] = None
    report = dict(selected_candidate=winner.candidate, threshold=float(winner.threshold),
                  selection_rule=bundle['selection_rule'], test_evaluated=False,
                  later_check='2021 was already included in the earlier validation report; this is not a new untouched holdout.',
                  baseline_2021=baseline, feature_groups=groups,
                  labelled_data_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                  caveats=['Daily F1 selection may sacrifice first-day detection.', 'Flow-only and rainfall-only both retain season and cell identity.',
                           'Validation exploration is not final test evidence.', 'All inputs and targets remain retrospective model estimates.'])
    (out / 'comparison_summary.json').write_text(json.dumps(report, indent=2))
    assert prediction.date.max() < '2022-01-01'
    # Confirm the persisted candidate reproduces its saved scores.
    loaded = joblib.load(model_dir / 'provisional_selected.joblib')
    expected = prediction[prediction.candidate == winner.candidate].score.to_numpy()
    assert np.allclose(loaded['model'].predict_proba(valid[loaded['features']])[:, 1], expected)
    print(default[['candidate', 'precision', 'recall', 'f1', 'onset_recall']].round(3).to_string(index=False))
    print('\nSelected using 2019–2020:', winner.candidate, 'threshold:', winner.threshold)
    print(checks[(checks.candidate == winner.candidate) & (checks.period == '2021_check')].round(3).to_string(index=False))
    print('Persistence in 2021:', baseline)
    return report

if __name__ == '__main__':
    compare_inputs()
