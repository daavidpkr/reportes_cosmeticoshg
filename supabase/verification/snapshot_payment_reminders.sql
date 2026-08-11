select
  (select count(*) from public.payment_reminders) reminder_count,
  (select md5(coalesce(string_agg(
     id::text || ':' || payment_date::text || ':' || schedule_version::text || ':' || active::text,
     ',' order by id), '')) from public.payment_reminders) reminder_fingerprint,
  (select count(*) from public.payment_notification_events) event_count,
  (select count(*) from public.payment_notification_events where status='sent') sent_count,
  (select md5(coalesce(string_agg(
     id::text || ':' || status || ':' || schedule_version::text,
     ',' order by id), '')) from public.payment_notification_events) event_fingerprint;
