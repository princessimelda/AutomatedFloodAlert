"""Audit model drainage areas and collect a fixed historical study period."""
from pathlib import Path
from io import BytesIO
from datetime import datetime, timezone
import json
import hashlib
import pandas as pd
import geopandas as gpd
import rasterio
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
ROOT=Path(__file__).resolve().parents[1]

def collect_history():
    out=ROOT/'data/processed/river_history'
    raw=ROOT/'data/raw/river_history'
    out.mkdir(parents=True,exist_ok=True)
    raw.mkdir(parents=True,exist_ok=True)
    pilot=ROOT/'data/processed/flood_api_pilot'
    sites=pd.read_csv(pilot/'requested_sites.csv').merge(pd.read_csv(pilot/'site_cell_mapping.csv'),on='site_id',validate='one_to_one')
    rivers=gpd.read_file(BytesIO((ROOT/'data/processed/rivers/nearby_hydrorivers.geojson').read_bytes()))
    sites=sites.merge(rivers[['HYRIV_ID','UPLAND_SKM']],on='HYRIV_ID',validate='one_to_one')
    auxiliary=ROOT/'data/raw/glofas_auxiliary/uparea_glofas_v4_0.nc'
    with rasterio.open(auxiliary) as src:
        assert src.tags()['uparea#units']=='m2'
        sites['glofas_upstream_km2']=[float(v[0])/1e6 for v in src.sample(zip(sites.returned_longitude,sites.returned_latitude))]
    sites['area_ratio']=sites.glofas_upstream_km2/sites.UPLAND_SKM
    sites['match_status']='Area comparison only; river identity not confirmed'
    sites['flow_review']=''
    sites.loc[sites.cell_id=='glofas_cell_02','flow_review']='Low pilot flow despite large upstream area; unresolved'
    sites.to_csv(out/'river_cell_audit.csv',index=False)
    source={'url':'https://confluence.ecmwf.int/download/attachments/242067380/uparea_glofas_v4_0.nc?version=2&modificationDate=1668604690076&api=v2',
            'documentation':'https://confluence.ecmwf.int/pages/viewpage.action?pageId=242067380',
            'sha256':hashlib.sha256(auxiliary.read_bytes()).hexdigest(),'units':'m2','sampling':'Cell containing the API returned longitude and latitude'}
    (out/'auxiliary_source.json').write_text(json.dumps(source,indent=2))
    cells=sites.sort_values('site_id').drop_duplicates('cell_id').sort_values('cell_id')
    cells.to_csv(out/'study_cells.csv',index=False)
    session=requests.Session()
    session.mount('https://',HTTPAdapter(max_retries=Retry(total=3,backoff_factor=1,status_forcelist=[429,500,502,503,504])))
    records=[]
    manifests=[]
    for start,end in [(2010,2014),(2015,2019),(2020,2024)]:
        params={'latitude':','.join(cells.returned_latitude.astype(str)), 'longitude':','.join(cells.returned_longitude.astype(str)),
                'start_date':f'{start}-01-01','end_date':f'{end}-12-31','daily':'river_discharge','models':'consolidated_v4','cell_selection':'nearest'}
        key=hashlib.sha256(json.dumps(params,sort_keys=True).encode()).hexdigest()[:16]
        path=raw/f'{key}.json'
        if not path.exists():
            response=session.get('https://flood-api.open-meteo.com/v1/flood',params=params,timeout=120)
            response.raise_for_status()
            payload={'parameters':params,'retrieved_at_utc':datetime.now(timezone.utc).isoformat(),'response':response.json()}
            path.write_text(json.dumps(payload,indent=2))
        payload=json.loads(path.read_text())
        data=payload['response']
        assert len(data)==len(cells)
        expected=pd.date_range(params['start_date'],params['end_date']).strftime('%Y-%m-%d').tolist()
        for site,item in zip(cells.itertuples(),data):
            assert abs(item['latitude']-site.returned_latitude)<.001 and abs(item['longitude']-site.returned_longitude)<.001
            assert item['daily']['time']==expected
            assert item['daily_units']['river_discharge']=='m³/s' and item['utc_offset_seconds']==0
            for date,value in zip(item['daily']['time'],item['daily']['river_discharge']):
                records.append({'cell_id':site.cell_id,'date':date,'river_discharge_m3s':value})
        manifests.append({'file':path.name,'parameters':params,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    flow=pd.DataFrame(records).sort_values(['cell_id','date'])
    assert not flow.duplicated(['cell_id','date']).any()
    assert (flow.river_discharge_m3s.dropna()>=0).all()
    flow['year']=pd.to_datetime(flow.date).dt.year
    flow['partition']=flow.year.map(lambda y:'train' if y<=2018 else 'validation' if y<=2021 else 'test')
    flow.to_csv(out/'daily_discharge_2010_2024.csv',index=False)
    coverage=flow.groupby(['cell_id','year']).river_discharge_m3s.agg(days='size',available='count',minimum='min',maximum='max',unique_values='nunique').reset_index()
    coverage['missing']=coverage.days-coverage.available
    coverage.to_csv(out/'annual_coverage.csv',index=False)
    (raw/'manifest.json').write_text(json.dumps(manifests,indent=2))
    summary={'cells':len(cells),'rows':len(flow),'missing':int(flow.river_discharge_m3s.isna().sum()),'period':'2010-01-01 through 2024-12-31',
             'train':'2010–2018','validation':'2019–2021','test':'2022–2024',
             'purpose':'Retrospective simulated high-flow research; river identity remains provisional. No threshold or model fitted.'}
    (out/'history_summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary,indent=2))
    return summary
if __name__=='__main__':
    collect_history()
