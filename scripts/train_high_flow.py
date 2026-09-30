"""Train retrospective high-flow models and evaluate validation years only."""
from pathlib import Path
import json, hashlib, importlib.metadata
import numpy as np
import pandas as pd
import joblib
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import precision_score,recall_score,f1_score,roc_auc_score,average_precision_score,confusion_matrix
from xgboost import XGBClassifier
ROOT=Path(__file__).resolve().parents[1]

def train_models():
    source=ROOT/'data/processed/river_history'
    out=ROOT/'data/processed/high_flow_models';out.mkdir(parents=True,exist_ok=True)
    models_dir=ROOT/'models/high_flow_experiment';models_dir.mkdir(parents=True,exist_ok=True)
    flow=pd.read_csv(source/'daily_discharge_2010_2024.csv')
    weather=pd.read_csv(source/'model_weather_2010_2024.csv')
    data=flow.merge(weather[['cell_id','date','rain_mm']],on=['cell_id','date'],validate='one_to_one').sort_values(['cell_id','date'])
    thresholds=data[data.partition=='train'].groupby('cell_id').river_discharge_m3s.quantile(.95)
    assert (thresholds>0).all()
    thresholds.rename('training_q95_m3s').to_csv(out/'training_thresholds.csv')
    data['threshold']=data.cell_id.map(thresholds)
    data['high_flow']=(data.river_discharge_m3s>data.threshold).astype(int)
    group=data.groupby('cell_id',sort=False)
    for lag in [1,2,3,7]:
        data[f'flow_lag{lag}_ratio']=group.river_discharge_m3s.shift(lag)/data.threshold
    for window in [3,7]:
        data[f'flow_mean{window}_ratio']=group.river_discharge_m3s.transform(lambda s:s.shift(1).rolling(window).mean())/data.threshold
    for window in [1,3,7]:
        data[f'rain_prev{window}_mm']=group.rain_mm.transform(lambda s:s.shift(1).rolling(window).sum())
    data['flow_change_ratio']=data.flow_lag1_ratio-data.flow_lag2_ratio
    day=pd.to_datetime(data.date).dt.dayofyear
    data['season_sin']=np.sin(2*np.pi*day/365.25);data['season_cos']=np.cos(2*np.pi*day/365.25)
    for cell in sorted(data.cell_id.unique()):data[f'is_{cell}']=(data.cell_id==cell).astype(int)
    data['previous_high']=group.high_flow.shift(1)
    data['onset']=(data.high_flow==1)&(data.previous_high==0)
    features=[c for c in data if c.startswith(('flow_lag','flow_mean','rain_prev','is_'))]+['flow_change_ratio','season_sin','season_cos']
    usable=data.dropna(subset=features+['previous_high']).copy()
    assert len(usable)==len(data)-35
    # Check lag and rainfall windows against their original observations.
    for _, rows in data.groupby('cell_id'):
        for idx in [7,1000,3287]:
            row=rows.iloc[idx]
            assert np.isclose(row.flow_lag1_ratio,rows.iloc[idx-1].river_discharge_m3s/row.threshold)
            assert np.isclose(row.rain_prev7_mm,rows.iloc[idx-7:idx].rain_mm.sum())
    usable.to_csv(out/'labelled_research_dataset.csv',index=False)
    train=usable[usable.partition=='train'];valid=usable[usable.partition=='validation']
    assert train.date.max()<valid.date.min()
    y=valid.high_flow.to_numpy()
    rows=[];prediction_tables=[];cell_scores=[]
    def evaluate(name,score,prediction):
        tn,fp,fn,tp=confusion_matrix(y,prediction,labels=[0,1]).ravel()
        onset=valid.onset.to_numpy();quiet=valid.previous_high.to_numpy()==0
        rows.append(dict(model=name,precision=precision_score(y,prediction,zero_division=0),recall=recall_score(y,prediction,zero_division=0),f1=f1_score(y,prediction,zero_division=0),roc_auc=roc_auc_score(y,score),average_precision=average_precision_score(y,score),true_negatives=int(tn),false_positives=int(fp),false_negatives=int(fn),true_positives=int(tp),onsets=int(onset.sum()),onset_recall=float(prediction[onset].mean()),onset_alert_precision=float(((prediction==1)&onset).sum()/max(1,((prediction==1)&quiet).sum()))))
        table=valid[['cell_id','date','high_flow','onset']].copy();table['model']=name;table['score']=score;table['prediction']=prediction
        prediction_tables.append(table)
        for cell,g in table.groupby('cell_id'):
            cell_scores.append(dict(model=name,cell_id=cell,precision=precision_score(g.high_flow,g.prediction,zero_division=0),recall=recall_score(g.high_flow,g.prediction,zero_division=0),f1=f1_score(g.high_flow,g.prediction,zero_division=0)))
    evaluate('always_low',np.zeros(len(valid)),np.zeros(len(valid),dtype=int))
    evaluate('persistence',valid.flow_lag1_ratio.to_numpy(),valid.previous_high.to_numpy().astype(int))
    candidates={
      'logistic_regression':make_pipeline(StandardScaler(),LogisticRegression(max_iter=2000,class_weight='balanced',random_state=42)),
      'random_forest':RandomForestClassifier(n_estimators=250,max_depth=10,min_samples_leaf=10,class_weight='balanced_subsample',random_state=42,n_jobs=2),
      'xgboost':XGBClassifier(n_estimators=250,max_depth=3,learning_rate=.05,subsample=.8,colsample_bytree=.8,reg_lambda=5,scale_pos_weight=float((train.high_flow==0).sum()/(train.high_flow==1).sum()),random_state=42,n_jobs=2,eval_metric='logloss')}
    for name,model in candidates.items():
        model.fit(train[features],train.high_flow)
        score=model.predict_proba(valid[features])[:,1]
        evaluate(name,score,(score>=.5).astype(int))
        joblib.dump(dict(model=model,features=features,thresholds=thresholds.to_dict(),decision_threshold=.5,target='Next GMT day exceeding training-cell Q95 simulated discharge',status='Research candidate; not approved for live alerts'),models_dir/f'{name}.joblib')
    metrics=pd.DataFrame(rows)
    metrics.to_csv(out/'validation_metrics.csv',index=False)
    pd.concat(prediction_tables).to_csv(out/'validation_predictions.csv',index=False)
    pd.DataFrame(cell_scores).to_csv(out/'validation_metrics_by_cell.csv',index=False)
    metadata={'training_rows':len(train),'validation_rows':len(valid),'held_out_test_rows':int((usable.partition=='test').sum()),'test_evaluated':False,'threshold_quantile':.95,'label_rule':'discharge > training Q95 for that cell','decision_threshold':.5,'seed':42,'features':features,'versions':{p:importlib.metadata.version(p) for p in ['pandas','numpy','scikit-learn','xgboost','joblib']},'data_sha256':hashlib.sha256((out/'labelled_research_dataset.csv').read_bytes()).hexdigest(),'limitations':['Reconstructed inputs are not guaranteed available at issue time.','Point rainfall is not upstream catchment rainfall.','Model cells and dates are correlated.','Cell 02 has unresolved low-flow behaviour.','High-flow labels are simulated targets, not observed floods.'],'persistence_score':'Continuous previous-day flow / training threshold for ranking metrics; classification repeats previous high-flow status.'}
    (out/'experiment_metadata.json').write_text(json.dumps(metadata,indent=2))
    print(metrics.round(3).to_string(index=False));print('Final test period remains unevaluated.')
    return metrics
if __name__=='__main__':train_models()
