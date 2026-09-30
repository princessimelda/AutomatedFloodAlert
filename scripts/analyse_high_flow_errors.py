"""Describe validation errors without refitting models or evaluating test years."""
from pathlib import Path
import json
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]


def analyse_errors():
    source = ROOT / 'data/processed/high_flow_models'
    out = source / 'error_analysis'
    out.mkdir(parents=True, exist_ok=True)
    data = pd.read_csv(source / 'labelled_research_dataset.csv')
    validation = data[data.partition == 'validation'].copy()
    predictions = pd.read_csv(source / 'validation_predictions.csv')
    assert predictions.date.min() == '2019-01-01'
    assert predictions.date.max() == '2021-12-31'
    assert not predictions.duplicated(['model', 'cell_id', 'date']).any()
    assert validation.groupby('cell_id').size().eq(1096).all()
    assert ((validation.river_discharge_m3s > validation.threshold).astype(int) == validation.high_flow).all()
    joined = predictions.merge(validation[['cell_id', 'date', 'river_discharge_m3s', 'threshold', 'previous_high', 'partition']],
                               on=['cell_id', 'date'], validate='many_to_one')
    assert joined.partition.eq('validation').all()
    joined['date'] = pd.to_datetime(joined.date)
    joined['year'] = joined.date.dt.year
    joined['flow_ratio'] = joined.river_discharge_m3s / joined.threshold
    joined['false_alarm'] = joined.prediction.eq(1) & joined.high_flow.eq(0)
    joined['miss'] = joined.prediction.eq(0) & joined.high_flow.eq(1)
    joined['true_alert'] = joined.prediction.eq(1) & joined.high_flow.eq(1)
    joined['negative_day'] = joined.high_flow.eq(0)
    # Future target values are used only to describe errors, never as predictors.
    annotated = []
    episodes = []
    for (model, cell), group in joined.groupby(['model', 'cell_id']):
        group = group.sort_values('date').copy()
        dates = group.date.to_numpy(dtype='datetime64[D]')
        high = group.high_flow.to_numpy() == 1
        high_dates = dates[high]
        distances = np.full(len(group), np.inf)
        next_distances = np.full(len(group), np.inf)
        previous_distances = np.full(len(group), np.inf)
        if len(high_dates):
            for i, day in enumerate(dates):
                delta = (high_dates - day).astype('timedelta64[D]').astype(int)
                distances[i] = np.abs(delta).min()
                if (delta > 0).any(): next_distances[i] = delta[delta > 0].min()
                if (delta < 0).any(): previous_distances[i] = -delta[delta < 0].max()
        group['days_to_next_high'] = next_distances
        group['days_since_previous_high'] = previous_distances
        before = next_distances <= 3
        after = previous_distances <= 3
        boundary = ((dates - dates[0]).astype(int) < 3) | ((dates[-1] - dates).astype(int) < 3)
        group['timing_context'] = np.select([before & after, before, after, boundary],
            ['between_high_days_within_3d', 'before_high_within_3d', 'after_high_within_3d', 'window_boundary_uncertain'],
            default='no_high_within_3d')
        # Near means within ten percent below the fixed flow threshold.
        group['near_target_threshold'] = group.flow_ratio.between(.9, 1, inclusive='both') & ~high
        alert = group.prediction.to_numpy() == 1
        starts = np.flatnonzero(alert & ~np.r_[False, alert[:-1]])
        ends = np.flatnonzero(alert & ~np.r_[alert[1:], False])
        for start, end in zip(starts, ends):
            span = group.iloc[start:end + 1]
            episodes.append(dict(model=model, cell_id=cell, start_date=span.date.iloc[0].date().isoformat(),
                end_date=span.date.iloc[-1].date().isoformat(), alert_days=len(span),
                high_days=int(span.high_flow.sum()), false_alarm_days=int(span.false_alarm.sum()),
                overlaps_high=bool(span.high_flow.any()), starts_on_low_day=bool(span.high_flow.iloc[0] == 0),
                touches_window_boundary=bool(start == 0 or end == len(group)-1)))
        annotated.append(group)
    joined = pd.concat(annotated, ignore_index=True)
    assert len(joined) == len(predictions)
    joined.to_csv(out / 'validation_error_details.csv', index=False)
    episode_table = pd.DataFrame(episodes)
    episode_table.to_csv(out / 'alert_episodes.csv', index=False)

    def summarise(group):
        alerts = int(group.prediction.sum())
        negatives = int(group.negative_day.sum())
        positives = int(group.high_flow.sum())
        onset = group.onset.astype(bool)
        return pd.Series(dict(rows=len(group), high_days=positives, prevalence=positives/len(group),
            alerts=alerts, false_alarm_days=int(group.false_alarm.sum()), missed_high_days=int(group['miss'].sum()),
            precision=float(group.true_alert.sum()/alerts) if alerts else np.nan,
            recall=float(group.true_alert.sum()/positives) if positives else np.nan,
            false_positive_rate=float(group.false_alarm.sum()/negatives) if negatives else np.nan,
            false_alarms_per_100_cell_days=100*float(group.false_alarm.mean()),
            onsets=int(onset.sum()), detected_onsets=int((onset & group.prediction.eq(1)).sum())))
    for keys, filename in [(['model'], 'model_summary.csv'), (['model', 'year'], 'by_year.csv'),
                           (['model', 'cell_id'], 'by_cell.csv'), (['model', 'cell_id', 'year'], 'by_cell_year.csv')]:
        result = joined.groupby(keys).apply(summarise, include_groups=False).reset_index()
        result.to_csv(out / filename, index=False)
    timing = joined[joined.false_alarm].groupby(['model', 'timing_context']).size().rename('false_alarm_days').reset_index()
    timing.to_csv(out / 'false_alarm_timing.csv', index=False)
    near = []
    for model, group in joined.groupby('model'):
        for label, subset in [('false_alarm_days', group[group.false_alarm]), ('all_negative_days', group[group.negative_day]),
                              ('missed_high_days', group[group['miss']])]:
            near.append(dict(model=model, subset=label, days=len(subset), median_actual_flow_ratio=float(subset.flow_ratio.median()) if len(subset) else None,
                near_below_threshold_days=int(subset.near_target_threshold.sum()),
                near_below_threshold_fraction=float(subset.near_target_threshold.mean()) if len(subset) else None))
    pd.DataFrame(near).to_csv(out / 'threshold_proximity.csv', index=False)
    episode_summary = episode_table.groupby('model').agg(alert_episodes=('alert_days', 'size'),
        overlapping_episodes=('overlaps_high', 'sum'), alert_days=('alert_days', 'sum'),
        episodes_starting_on_low_day=('starts_on_low_day', 'sum'), boundary_episodes=('touches_window_boundary', 'sum')).reset_index()
    episode_summary['episodes_without_high_day'] = episode_summary.alert_episodes - episode_summary.overlapping_episodes
    episode_summary.to_csv(out / 'episode_summary.csv', index=False)
    # Show the flagged cell's influence without removing it from the experiment.
    sensitivity = []
    for model, group in joined.groupby('model'):
        for scope, subset in [('all_cells', group), ('without_flagged_cell_02', group[group.cell_id != 'glofas_cell_02'])]:
            sensitivity.append(dict(model=model, scope=scope, **summarise(subset).to_dict()))
    pd.DataFrame(sensitivity).to_csv(out / 'flagged_cell_sensitivity.csv', index=False)
    for model, group in joined.groupby('model'):
        assert len(group) == 5480
        assert group.false_alarm.sum() + group.true_alert.sum() == group.prediction.sum()
        ep = episode_table[episode_table.model == model]
        assert ep.alert_days.sum() == group.prediction.sum()
        assert ep.false_alarm_days.sum() == group.false_alarm.sum()
    policy = dict(period='2019–2021 validation only', test_evaluated=False, models_refitted=False,
        predictions='Original candidates at score threshold 0.5; persistence repeats previous-day status.',
        near_threshold_definition='Actual simulated flow between 90% and 100% of training Q95, inclusive.',
        timing_window_days=3, episode_definition='Consecutive alert days within a model cell; gaps end an episode.',
        interpretation=['Timing and proximity are post-hoc descriptions, not revised correctness labels.',
                        'An episode overlapping one high day may still contain many false-alarm days.',
                        'Episodes are not independent observed flood incidents.',
                        'Validation boundaries may truncate episodes or hide adjacent high days.',
                        'No significance or causality is inferred from these descriptive counts.'])
    (out / 'analysis_notes.json').write_text(json.dumps(policy, indent=2))
    print(pd.read_csv(out / 'model_summary.csv').round(3).to_string(index=False))
    print('\nTiming:\n', timing.to_string(index=False))
    print('\nEpisodes:\n', episode_summary.to_string(index=False))
    return out

if __name__ == '__main__':
    analyse_errors()
