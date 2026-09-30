"""Download consistent GMT rainfall for the five research cells."""
from pathlib import Path
from datetime import datetime, timezone
import json, hashlib
import pandas as pd
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
ROOT=Path(__file__).resolve().parents[1]
def collect_weather():
    cells=pd.read_csv(ROOT/'data/processed/river_history/study_cells.csv').sort_values('cell_id')
    raw=ROOT/'data/raw/model_weather';raw.mkdir(parents=True,exist_ok=True)
    out=ROOT/'data/processed/river_history'
    session=requests.Session();session.mount('https://',HTTPAdapter(max_retries=Retry(total=3,backoff_factor=1,status_forcelist=[429,500,502,503,504])))
    rows=[];manifest=[]
    for start,end in [(2010,2014),(2015,2019),(2020,2024)]:
        params=dict(latitude=','.join(cells.returned_latitude.astype(str)),longitude=','.join(cells.returned_longitude.astype(str)),start_date=f'{start}-01-01',end_date=f'{end}-12-31',daily='precipitation_sum',timezone='GMT',models='era5')
        path=raw/(hashlib.sha256(json.dumps(params,sort_keys=True).encode()).hexdigest()[:16]+'.json')
        if not path.exists():
            reply=session.get('https://archive-api.open-meteo.com/v1/archive',params=params,timeout=120);reply.raise_for_status()
            path.write_text(json.dumps(dict(parameters=params,retrieved_at_utc=datetime.now(timezone.utc).isoformat(),response=reply.json()),indent=2))
        data=json.loads(path.read_text())['response'];assert len(data)==len(cells)
        for site,item in zip(cells.itertuples(),data):
            assert item['utc_offset_seconds']==0 and item['daily_units']['precipitation_sum']=='mm'
            assert item['daily']['time']==pd.date_range(params['start_date'],params['end_date']).strftime('%Y-%m-%d').tolist()
            for date,rain in zip(item['daily']['time'],item['daily']['precipitation_sum']):
                rows.append(dict(cell_id=site.cell_id,date=date,rain_mm=rain,weather_latitude=item['latitude'],weather_longitude=item['longitude']))
        manifest.append(dict(file=path.name,parameters=params,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    weather=pd.DataFrame(rows).sort_values(['cell_id','date']);assert len(weather)==27395
    assert not weather.duplicated(['cell_id','date']).any()
    assert weather.rain_mm.notna().all() and (weather.rain_mm>=0).all()
    weather.to_csv(out/'model_weather_2010_2024.csv',index=False)
    (raw/'manifest.json').write_text(json.dumps(manifest,indent=2))
    print('Weather rows:',len(weather),'Distinct returned weather cells:',len(weather[['weather_latitude','weather_longitude']].drop_duplicates()))
    return weather
if __name__=='__main__':collect_weather()
