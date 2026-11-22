# Research models

The current packaged experimental rainfall model is described in the
[versioned inference contract](INFERENCE_CONTRACT.md) (#5). Its frozen bundle
supports the cloud worker; backend and Flutter consumption remain #8/#13.

Saved model experiments for the Nairobi flood-alert research project. Training and evaluation code is maintained in `../scripts/`, with exploratory work in `../weatherdata.ipynb`.

The experiments compare logistic regression, random forest, and XGBoost, including input and class-weight variants. Their high-flow targets are based on simulated discharge rather than verified flood observations. These artifacts are research candidates, not approved live-alert models.

Training datasets and generated evaluation reports remain local under `data/` and are excluded from this repository. Loading the artifacts requires a compatible Python environment and the corresponding modelling libraries.
