"""Change class weighting only; assess fixed validation predictions by year."""
from pathlib import Path
import hashlib
import json
import joblib
import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.metrics import precision_score, recall_score, f1_score, average_precision_score, roc_auc_score
ROOT = Path(__file__).resolve().parents[1]


def compare_weights():
    source = ROOT / 'data/processed/high_flow_models'
    out = source / 'weight_comparison'
    out.mkdir(parents=True, exist_ok=True)
    saved = ROOT / 'models/high_flow_experiment'
    destination = saved / 'weight_comparison'
    destination.mkdir(parents=True, exist_ok=True)
    path = source / 'labelled_research_dataset.csv'
    meta = json.loads((source / 'experiment_metadata.json').read_text())
    assert hashlib.sha256(path.read_bytes()).hexdigest() == meta['data_sha256']
    data = pd.read_csv(path)
    data = data[data.partition.isin(['train', 'validation'])].copy()
    train = data[data.partition == 'train']
    valid = data[data.partition == 'validation'].sort_values(['cell_id', 'date'])
    assert train.date.max() < valid.date.min() and valid.date.max() < '2022-01-01'
    negatives = int(train.high_flow.eq(0).sum())
    positives = int(train.high_flow.eq(1).sum())
    ratio = negatives / positives
    mild_ratio = np.sqrt(ratio)
    # Normalise sample weights to mean one for the sklearn models.
    base_weight = len(train) / (negatives + mild_ratio * positives)
    mild_weights = {0: base_weight, 1: base_weight * mild_ratio}
    original_scores = pd.read_csv(source / 'validation_predictions.csv')
    predictions = []
    settings = []
    for name in ['logistic_regression', 'random_forest', 'xgboost']:
        original = joblib.load(saved / f'{name}.joblib')
        features = original['features']
        for weighting in ['original', 'mild', 'none']:
            model = original['model'] if weighting == 'original' else clone(original['model'])
            if weighting != 'original':
                if name == 'logistic_regression':
                    model.set_params(logisticregression__class_weight=mild_weights if weighting == 'mild' else None)
                elif name == 'random_forest':
                    model.set_params(class_weight=mild_weights if weighting == 'mild' else None)
                else:
                    model.set_params(scale_pos_weight=float(mild_ratio) if weighting == 'mild' else 1.0)
                model.fit(train[features], train.high_flow)
            scores = model.predict_proba(valid[features])[:, 1]
            if weighting == 'original':
                old = original_scores[original_scores.model == name].sort_values(['cell_id', 'date'])
                assert np.allclose(scores, old.score)
            table = valid[['cell_id', 'date', 'high_flow', 'onset']].copy()
            table['model'] = name
            table['weighting'] = weighting
            table['score'] = scores
            table['prediction'] = (scores >= .5).astype(int)
            predictions.append(table)
            bundle = {**original, 'model': model, 'decision_threshold': .5,
                      'weighting': weighting, 'status': 'Weighting experiment; no final test evaluation'}
            joblib.dump(bundle, destination / f'{name}__{weighting}.joblib')
            loaded = joblib.load(destination / f'{name}__{weighting}.joblib')
            assert np.allclose(loaded['model'].predict_proba(valid[features])[:, 1], scores)
            settings.append(dict(model=name, weighting=weighting,
                positive_to_negative_weight_ratio=ratio if weighting == 'original' else float(mild_ratio) if weighting == 'mild' else 1,
                note='Original random forest balances each bootstrap sample; others use training-set ratios.'))
    baseline = original_scores[original_scores.model == 'persistence'].copy()
    baseline['weighting'] = 'baseline'
    predictions.append(baseline)
    predictions = pd.concat(predictions, ignore_index=True)
    assert predictions.date.max() < '2022-01-01'
    predictions.to_csv(out / 'validation_predictions.csv', index=False)

    def metrics(table):
        y = table.high_flow.to_numpy()
        p = table.prediction.to_numpy()
        onset = table.onset.astype(bool).to_numpy()
        total_episodes = 0
        entirely_false = 0
        boundary_episodes = 0
        for _, g in table.groupby('cell_id'):
            g = g.sort_values('date')
            flags = g.prediction.to_numpy() == 1
            starts = np.flatnonzero(flags & ~np.r_[False, flags[:-1]])
            ends = np.flatnonzero(flags & ~np.r_[flags[1:], False])
            for start, end in zip(starts, ends):
                total_episodes += 1
                entirely_false += int(not g.high_flow.iloc[start:end+1].any())
                boundary_episodes += int(start == 0 or end == len(g)-1)
        return dict(rows=len(table), high_days=int(y.sum()), precision=precision_score(y,p,zero_division=0),
            recall=recall_score(y,p,zero_division=0), f1=f1_score(y,p,zero_division=0),
            average_precision=average_precision_score(y,table.score) if y.sum() else np.nan,
            roc_auc=roc_auc_score(y,table.score) if len(np.unique(y)) == 2 else np.nan,
            false_alarm_days=int(((p==1)&(y==0)).sum()), missed_high_days=int(((p==0)&(y==1)).sum()),
            onsets=int(onset.sum()), detected_onsets=int(((p==1)&onset).sum()),
            onset_recall=float(p[onset].mean()) if onset.any() else np.nan,
            alert_episodes=total_episodes, entirely_false_episodes=entirely_false,
            episodes_touching_period_boundary=boundary_episodes)
    results = []
    cell_results = []
    for (model, weighting), group in predictions.groupby(['model', 'weighting']):
        for period in ['all_validation','2019','2020','2021']:
            subset = group if period == 'all_validation' else group[group.date.str.startswith(period)]
            results.append(dict(model=model,weighting=weighting,period=period,**metrics(subset)))
        for cell, subset in group.groupby('cell_id'):
            cell_results.append(dict(model=model,weighting=weighting,cell_id=cell,**metrics(subset)))
    results = pd.DataFrame(results)
    results.to_csv(out / 'validation_metrics.csv', index=False)
    pd.DataFrame(cell_results).to_csv(out / 'by_cell.csv', index=False)
    changes = []
    for name in ['logistic_regression','random_forest','xgboost']:
        for period in ['all_validation','2019','2020','2021']:
            group = results[(results.model==name)&(results.period==period)].set_index('weighting')
            for weighting in ['mild','none']:
                changes.append(dict(model=name,weighting=weighting,period=period,
                    fewer_false_alarm_days=int(group.loc['original','false_alarm_days']-group.loc[weighting,'false_alarm_days']),
                    additional_missed_high_days=int(group.loc[weighting,'missed_high_days']-group.loc['original','missed_high_days']),
                    change_in_detected_onsets=int(group.loc[weighting,'detected_onsets']-group.loc['original','detected_onsets'])))
    pd.DataFrame(changes).to_csv(out / 'changes_from_original.csv',index=False)
    pd.DataFrame(settings).to_csv(out / 'weight_settings.csv',index=False)
    summary=dict(test_evaluated=False,training_period='2010–2018',validation_period='2019–2021',
        approach='Fixed training period, chronological yearly validation breakdown; not rolling cross-validation.',
        changed='Class weighting only; combined inputs, random seed, other hyperparameters and score threshold 0.5 fixed.',
        negative_positive_ratio=ratio,mild_ratio=float(mild_ratio),
        selection='No winner selected; report false alarms and missed onsets together.',
        caveats=['Scores are not calibrated probabilities.','Year-specific episodes can be truncated at year boundaries.',
                 'A fixed 0.5 threshold compares operating behaviour, not best achievable precision at equal recall.',
                 'Modelled flow targets and reconstructed inputs are not independent observed flood evidence.'],
        data_sha256=meta['data_sha256'],versions=meta['versions'])
    (out/'experiment_summary.json').write_text(json.dumps(summary,indent=2))
    print(results[results.period=='all_validation'][['model','weighting','precision','recall','f1','false_alarm_days','missed_high_days','detected_onsets','entirely_false_episodes']].round(3).to_string(index=False))
    return summary

if __name__ == '__main__':
    compare_weights()
