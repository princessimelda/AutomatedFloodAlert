# Rainfall inference contract — v1

Issue #5. This contract applies to the frozen `openmeteo_rainfall_v1` package,
which supersedes the older high-flow candidate for experimental app integration.
It does not establish a validated flood-warning model.

## Release identity

The authoritative machine-readable release is [bundle.json](openmeteo_rainfall_v1/bundle.json).
`bundle.sha256` checks that manifest; the manifest hashes every required model and
reference member. Checks run before loading the trusted repository joblib artifact.
Pinned NumPy/pandas/scikit-learn/joblib versions are enforced. Changed models,
features, target, grids or thresholds require a new reviewed release identity.

| Property | Frozen value |
| --- | --- |
| Contract | `rainfall-inference/v1` |
| Model | `nairobi-gfs-rainfall-lr-a5bacdf0368b` |
| Estimator | Validation-selected Logistic Regression; no runtime fitting |
| Source run | `20261103T200731Z_a824a6ce`; original run hash in manifest |
| Provider | Open-Meteo `gfs_global`, nearest native grid, native elevation, UTC days |
| Target | Daily provider rainfall above each grid's early-training wet-day Q95 |
| Decision | Score >= 0.5, distinct from the rainfall threshold in mm |
| Rain thresholds | Approximately 10.045 mm east and 10.370 mm west/south; exact grid-keyed values in manifest |

## Internal request

`infer_current(bundle, frame, snapshot, now=aware_datetime)` in
[`contract.py`](../scripts/weather_worker/contract.py) is the worker boundary.
It is not a public HTTP endpoint; API/Flutter consumption remains #8/#13.

The caller supplies a checksum-verified bundle and verified ingestion snapshot,
including raw-source checksums and frozen preprocessing compatibility. Arbitrary
client features are not trusted source evidence. `frame` has exactly one row for
each trained grid, target-day UTC midnight in `time`, and every predictor from
the manifest. The saved pipeline receives the manifest's exact predictor order.

| Predictors | Units / definition |
| --- | --- |
| latitude, longitude, elevation_m | Decimal degrees, decimal degrees, metres; trained native grid metadata |
| station_id | Exact provider grid ID; historical column name does not mean a physical station |
| rain_history_days | Count of prior rainfall days |
| season_sin, season_cos | Dimensionless calendar terms from the frozen transformer |
| tavg, tmin, tmax derivatives | Celsius |
| prcp derivatives / prcp_sum_prev7 | Millimetres |
| wspd derivatives | km/h at 10 metres |
| pres derivatives | hPa, mean sea-level pressure |

`lag1` and `lag2` use target minus one/two days; `mean_prev3`, `mean_prev7`
and `sum_prev7` exclude the target day. Source unit/grid checks precede feature
preparation. Missing weather is never replaced with zero. Today's partial weather
and future observations are excluded.

The snapshot requires `status: ready`, `provider_model: gfs_global`,
`target_date_utc`, `history_start_utc`, `history_end_utc`, `retrieved_at_utc`,
`completed_at_utc` and `expires_at_utc`. Dates are ISO YYYY-MM-DD; timestamps
carry timezones and are normalised to UTC. History is target minus seven through
minus one. Only the current UTC target date is accepted.

## Response and expiry

The JSON-serialisable response contains `contract_version`, `model_version`,
`bundle_sha256`, `target_kind: high_rainfall_proxy`, `experimental: true`,
`calibrated_flood_probability: false`, `score_threshold`, `limitations`,
`target_date_utc`, `input_retrieved_at_utc`, `generated_at_utc`,
`valid_until_utc` and `predictions`.

Each of the two prediction records has `grid_id`, `score` in [0,1],
`predicted_high_rainfall`, `rain_threshold_mm`, the exact `features` and
`feature_sha256`. A score is not millimetres or a calibrated flood probability.

Expiry is the earliest of snapshot expiry, retrieval plus two hours, and UTC
target-day end. A retrieval at 12:00 UTC expires by 14:00; one at 23:30 expires
at midnight. Future retrievals, timestamp disorder and naive clocks are rejected.
The worker stores the envelope without prediction rows in run metadata and
persists predictions/evidence atomically. Database views may further restrict
validity. Consumers must use `latest_status` / `current_predictions`; failed,
running, incomplete or expired latest runs do not fall back to older success.

## Failures and verification

`InferenceContractError.code` is a stable non-sensitive code: `invalid_timestamp`,
`missing_snapshot_fields`, `inputs_not_ready`, `invalid_date`,
`invalid_timestamp_order`, `stale_inputs`, `invalid_history_window`,
`provider_model_mismatch`, `missing_target_dates`, `target_date_mismatch`,
`missing_grid_ids`, or `invalid_predictors`. Invalid predictors include missing,
null, non-finite or nonnumeric features and duplicate/unknown grids. The worker
records the code; it does not publish new rows or substitute old scores.

With the [pinned dependencies](../scripts/weather_worker/requirements.txt), run:

```bash
python -m unittest discover -s tests -p test_weather_worker.py -v
# Guarded isolated localhost test database only; never Supabase:
FLOODSAFE_RUN_DB_TESTS=1 python -m unittest discover -s tests -p test_weather_worker.py -v
```

CI runs the same suite. Tests cover contract serialisation, unchanged scores,
release identity, absent/invalid features, grid membership, provider/window/date
compatibility, future/stale timestamps, UTC midnight, atomic writes, RLS and
failure visibility. Synthetic fixtures verify software behaviour, not accuracy.

## Interpretation limits

The held-out 2025 precision was 0.2558 and recall 0.8462 against the **rainfall
proxy**, not observed floods. Coarse GFS cells do not identify street-level
flooding, depth, safe destinations or passable roads. Live recent weather can
differ from historical forecast products; as-issued forecast lead-time validation
remains outstanding. Do not convert scores into low/moderate/high flood severity
or evacuation/SMS decisions without a separate validated hazard/alert policy.
See the [research method](../scripts/openmeteo_pipeline/README.md).
