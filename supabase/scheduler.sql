-- Optional Supabase database-owner setup. Do not run against an unrelated project.
-- Enables recurring expiry/commission/call cleanup without an external server secret.
create extension if not exists pg_cron;
select cron.unschedule(jobid) from cron.job where jobname='local-mate-operations-maintenance';
select cron.schedule('local-mate-operations-maintenance','*/5 * * * *','select private.run_maintenance();');
