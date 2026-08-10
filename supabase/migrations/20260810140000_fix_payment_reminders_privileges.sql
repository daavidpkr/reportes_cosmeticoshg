begin;

revoke execute on function public.register_fcm_device(text, text)
from public, anon;

revoke execute on function public.deactivate_fcm_device(text)
from public, anon;

grant execute on function public.register_fcm_device(text, text)
to authenticated, service_role;

grant execute on function public.deactivate_fcm_device(text)
to authenticated, service_role;

revoke delete on table public.payment_notification_events
from service_role;

commit;
