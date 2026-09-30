"""Compare fixed false-positive budgets and stress-test stale inputs."""
from pathlib import Path
import json
import hashlib
import numpy as np
import pandas as pd
import joblib
from sklearn.metrics import precision_score, recall_score, f1_score
ROOT = Path(__file__).resolve().parents[1]


def measures(table, threshold):
    y = table.high_flow.to_numpy(dtype=int)
    p = table.score.to_numpy() >= threshold
    onset = table.onset.to_numpy(dtype=bool)
    fp = int((p & (y == 0)).sum())
    negatives = int((y == 0).sum())
    return dict(rows=len(y), negative_days=negatives, high_days=int(y.sum()),
                false_alarm_days=fp, false_positive_rate=fp/negatives,
                precision=precision_score(y, p, zero_division=0), recall=recall_score(y, p, zero_division=0),
                f1=f1_score(y, p, zero_division=0), onsets=int(onset.sum()),
                detected_onsets=int((p & onset).sum()), onset_recall=float(p[onset].mean()))


def check_limits():
    root = ROOT / 'data/processed/high_flow_models'
    out = root / 'alert_limits'; out.mkdir(parents=True, exist_ok=True)
    scores = pd.read_csv(root/'weight_comparison/validation_predictions.csv')
    scores = scores[scores.model != 'persistence'].copy()
    scores['candidate'] = scores.model + '__' + scores.weighting
    assert scores.date.max() < '2022-01-01'
    caps = [.01, .02, .03]
    rows = []
    selections = []
    for candidate, table in scores.groupby('candidate'):
        early = table[table.date < '2021-01-01']
        later = table[table.date >= '2021-01-01']
        # Fixed grid includes an all-negative option for any tied scores of one.
        thresholds = np.r_[np.linspace(0, 1, 201), np.nextafter(1., 2.)]
        sweep = pd.DataFrame([dict(threshold=float(t), **measures(early, t)) for t in thresholds])
        for cap in caps:
            feasible = sweep[sweep.false_positive_rate <= cap]
            best = feasible.sort_values(['detected_onsets','recall','false_alarm_days','threshold'],
                                        ascending=[False,False,True,False]).iloc[0]
            selections.append(dict(candidate=candidate, cap=cap, threshold=float(best.threshold)))
            for period, subset in [('2019_2020_tuning',early),('2021_check',later)]:
                result = measures(subset, best.threshold)
                rows.append(dict(candidate=candidate, cap=cap, threshold=float(best.threshold), period=period,
                                 cap_met=result['false_positive_rate'] <= cap, **result))
    results = pd.DataFrame(rows)
    results.to_csv(out/'candidate_budget_results.csv', index=False)
    winners = []
    for cap in caps:
        early = results[(results.cap == cap)&(results.period == '2019_2020_tuning')]
        best = early.sort_values(['detected_onsets','recall','false_alarm_days','candidate'],
                                 ascending=[False,False,True,True]).iloc[0]
        winners.append(dict(cap=cap,candidate=best.candidate,threshold=float(best.threshold)))
    winner_table = pd.DataFrame(winners)
    winner_table.to_csv(out/'provisional_budget_choices.csv',index=False)
    # Existing models stay fixed. Delay only time-varying measured inputs.
    dataset = root/'labelled_research_dataset.csv'
    data = pd.read_csv(dataset)
    data = data[data.partition.isin(['train','validation'])].sort_values(['cell_id','date']).copy()
    later = data[data.date >= '2021-01-01'].copy()
    delay_rows = []
    delay_predictions = []
    for choice in winners:
        bundle = joblib.load(ROOT/'models/high_flow_experiment/weight_comparison'/f"{choice['candidate']}.joblib")
        features = bundle['features']
        temporal = [f for f in features if f.startswith(('flow_', 'rain_prev'))]
        for delay in [0,1,3,5]:
            delayed = data.copy()
            delayed[temporal] = data.groupby('cell_id')[temporal].shift(delay)
            available = delayed.loc[later.index]
            assert available[features].notna().all().all()
            assert available[['season_sin','season_cos']].equals(later[['season_sin','season_cos']])
            score = bundle['model'].predict_proba(available[features])[:,1]
            table = later[['cell_id','date','high_flow','onset']].copy()
            table['score'] = score
            if delay == 0:
                expected = scores[(scores.candidate == choice['candidate'])&(scores.date >= '2021-01-01')].sort_values(['cell_id','date'])
                assert np.allclose(score, expected.score)
            else:
                for _, cell in delayed.groupby('cell_id'):
                    idx = cell.index[cell.date == '2021-01-01'][0]
                    source_row = data[(data.cell_id == cell.cell_id.iloc[0])&(data.date == str(pd.Timestamp('2021-01-01').date()-pd.Timedelta(days=delay)))].iloc[0]
                    assert np.isclose(delayed.loc[idx,'flow_lag1_ratio'], source_row.flow_lag1_ratio)
            result = measures(table, choice['threshold'])
            delay_rows.append(dict(**choice,extra_delay_days=delay,newest_input_age_days=1+delay,
                                   cap_met=result['false_positive_rate']<=choice['cap'],**result))
            table['candidate']=choice['candidate'];table['cap']=choice['cap'];table['extra_delay_days']=delay
            table['prediction']=(score>=choice['threshold']).astype(int)
            delay_predictions.append(table)
    delay_results = pd.DataFrame(delay_rows)
    delay_results.to_csv(out/'delay_stress_results_2021.csv',index=False)
    pd.concat(delay_predictions).to_csv(out/'delay_stress_predictions_2021.csv',index=False)
    baseline = pd.read_csv(root/'validation_predictions.csv')
    baseline = baseline[(baseline.model=='persistence')&(baseline.date>='2021-01-01')].copy()
    baseline['score']=baseline.prediction
    baseline_result=measures(baseline,.5)
    summary=dict(test_evaluated=False,model_refitting=False,false_positive_caps=caps,
        denominator='Observed low-flow target cell-days, not all days or independent events.',
        threshold_selection='2019–2020 only: maximise detected onsets under cap, then daily recall, then fewer false alarms.',
        threshold_grid='0 to 1 at 0.005 steps, plus next float above 1 for no alerts.',
        delay_design='Fixed models and thresholds; all flow and rainfall features shifted within cell by 0,1,3,5 extra days. Season and cell identity retained.',
        delay_status='Hypothetical stress test; not a claim about actual provider latency and not delay-aware retraining.',
        check_period='2021; already inspected during development, not an independent holdout.',
        persistence_2021=baseline_result,data_sha256=hashlib.sha256(dataset.read_bytes()).hexdigest(),
        warning='Caps apply to tuning data and are not guarantees on later data. No operating limit or final model has been approved.')
    (out/'analysis_summary.json').write_text(json.dumps(summary,indent=2))
    selected = results.merge(winner_table,on=['cap','candidate','threshold'])
    selected.to_csv(out/'selected_budget_results.csv',index=False)
    print(selected[['cap','candidate','period','threshold','false_alarm_days','false_positive_rate','detected_onsets','onsets','cap_met']].round(4).to_string(index=False))
    print('\nDelay stress test:\n',delay_results[['cap','candidate','extra_delay_days','false_alarm_days','detected_onsets','onsets']].to_string(index=False))
    return summary

if __name__ == '__main__':
    check_limits()
