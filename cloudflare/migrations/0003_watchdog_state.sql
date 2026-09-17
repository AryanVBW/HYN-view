-- Heartbeat watchdog last-known online/offline state. Auth stays in Supabase.

ALTER TABLE node_watchdogs ADD COLUMN last_alert_state TEXT;
