select now() observed_at, d.runid, d.status, d.start_time, d.end_time,
       left(coalesce(d.return_message, ''), 300) return_message,
       j.schedule, j.active
from cron.job_run_details d
join cron.job j on j.jobid=d.jobid
where j.jobname='process-payment-reminders-production'
order by d.start_time desc
limit 5;
