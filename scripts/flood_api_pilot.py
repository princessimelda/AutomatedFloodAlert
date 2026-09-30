"""Check a small, explicitly selected GloFAS historical sample."""
from pathlib import Path
from io import BytesIO
from datetime import datetime, timezone
import hashlib
import json
import geopandas as gpd
import pandas as pd
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

ROOT = Path(__file__).resolve().parents[1]

def run_pilot():
    raw = ROOT / 'data/raw/flood_api_pilot'
    out = ROOT / 'data/processed/flood_api_pilot'
    raw.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    rivers = gpd.read_file(BytesIO((ROOT/'data/processed/rivers/nearby_hydrorivers.geojson').read_bytes())).to_crs(32737)
    county = gpd.read_file(BytesIO((ROOT/'data/processed/geography/nairobi_county.geojson').read_bytes())).to_crs(32737).geometry.union_all()
    rivers['geometry'] = rivers.geometry.intersection(county)
    rivers = rivers[~rivers.geometry.is_empty].sort_values(['UPLAND_SKM','HYRIV_ID'], ascending=[False,True])
    chosen = []
    for _, reach in rivers.iterrows():
        point = reach.geometry.interpolate(.5, normalized=True)
        if all(point.distance(p['geometry']) >= 5000 for p in chosen):
            chosen.append(dict(site_id=f'river_{int(reach.HYRIV_ID)}', HYRIV_ID=int(reach.HYRIV_ID), geometry=point))
        if len(chosen) == 6:
            break
    sites = gpd.GeoDataFrame(chosen, crs=32737).to_crs(4326)
    sites['latitude'] = sites.geometry.y
    sites['longitude'] = sites.geometry.x
    sites.drop(columns='geometry').to_csv(out/'requested_sites.csv', index=False)
    session = requests.Session()
    session.mount('https://', HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1, status_forcelist=[429,500,502,503,504])))
    records, summaries, provenance = [], [], []
    for year in (2018,2021,2024):
        params = dict(latitude=','.join(sites.latitude.astype(str)), longitude=','.join(sites.longitude.astype(str)),
                      start_date=f'{year}-04-01',end_date=f'{year}-04-30',daily='river_discharge',models='consolidated_v4')
        key = hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()[:16]
        path = raw/f'{key}.json'
        if not path.exists():
            response = session.get('https://flood-api.open-meteo.com/v1/flood',params=params,timeout=90)
            payload = dict(parameters=params,status_code=response.status_code,retrieved_at_utc=datetime.now(timezone.utc).isoformat(),response=response.json())
            path.write_text(json.dumps(payload,indent=2))
        saved = json.loads(path.read_text())
        provenance.append(dict(file=path.name,parameters=params,status_code=saved['status_code'],sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        if saved['status_code'] != 200:
            summaries.append(dict(year=year,status='request_failed',reason=str(saved['response'])))
            continue
        data = saved['response']
        if isinstance(data,dict): data=[data]
        assert len(data)==len(sites)
        for site, item in zip(sites.itertuples(),data):
            dates=item['daily']['time']
            values=item['daily']['river_discharge']
            assert len(dates)==30 and dates==pd.date_range(f'{year}-04-01',f'{year}-04-30').strftime('%Y-%m-%d').tolist()
            assert item['daily_units']['river_discharge']=='m³/s'
            series=pd.Series(values,dtype=float)
            assert (series.dropna()>=0).all()
            returned=gpd.GeoSeries(gpd.points_from_xy([item['longitude']],[item['latitude']]),crs=4326).to_crs(32737).iloc[0]
            requested=gpd.GeoSeries([site.geometry],crs=4326).to_crs(32737).iloc[0]
            summaries.append(dict(site_id=site.site_id,year=year,status='ok',returned_latitude=item['latitude'],returned_longitude=item['longitude'],offset_m=round(returned.distance(requested),1),missing_days=int(series.isna().sum()),unique_values=int(series.nunique()),minimum=series.min(),maximum=series.max(),timezone=item.get('timezone'),utc_offset_seconds=item.get('utc_offset_seconds')))
            for date,value in zip(dates,values):
                records.append(dict(site_id=site.site_id,date=date,river_discharge_m3s=value,model='consolidated_v4',returned_latitude=item['latitude'],returned_longitude=item['longitude']))
    daily=pd.DataFrame(records)
    checks=pd.DataFrame(summaries)
    daily.to_csv(out/'daily_discharge.csv',index=False)
    checks.to_csv(out/'coverage_checks.csv',index=False)
    (raw/'manifest.json').write_text(json.dumps(provenance,indent=2))
    print(checks.to_string(index=False))
    return checks

if __name__=='__main__':
    run_pilot()
