-- Disposable database only unless an operator has reviewed dependencies/backups.
DROP SCHEMA floodsafe_alerting CASCADE;
DROP POLICY alert_service_places ON public.places;
REVOKE SELECT ON public.places FROM floodsafe_alert_service;
-- Retain shared role; remove migration ledger entry only in the same rollback transaction.
