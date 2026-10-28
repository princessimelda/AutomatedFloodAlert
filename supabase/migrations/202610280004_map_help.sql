-- Keep the published guide aligned with the interactive map implementation.
UPDATE public.assistant_answers SET
 answer='FloodSafe now provides an interactive street map with device-location and neighbourhood markers. It does not provide verified evacuation routes or safe destinations. Map markers and neighbourhood centres do not identify flood boundaries or safe areas. Use Home to check assessment sources and validity; follow official local instructions.',
 source='FloodSafe interactive map implementation',
 source_url='https://github.com/princessimelda/AutomatedFloodAlert/tree/main/floodsafe/lib/maps',
 reviewed_at=now(), valid_until=now()+interval '90 days'
WHERE id='routes' AND language='en';
