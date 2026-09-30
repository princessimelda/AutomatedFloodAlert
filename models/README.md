# Research models

Saved model experiments for the Nairobi flood-alert research project. Training and evaluation code is maintained in `../scripts/`, with exploratory work in `../weatherdata.ipynb`.

The experiments compare logistic regression, random forest, and XGBoost, including input and class-weight variants. Their high-flow targets are based on simulated discharge rather than verified flood observations. These artifacts are research candidates, not approved live-alert models.

Training datasets and generated evaluation reports remain local under `data/` and are excluded from this repository. Loading the artifacts requires a compatible Python environment and the corresponding modelling libraries.
