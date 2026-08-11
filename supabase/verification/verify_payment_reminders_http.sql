select id, status_code, content_type, timed_out,
       left(coalesce(error_msg, ''), 200) error_message,
       case
         when content_type like 'application/json%'
           then left(content, 500)
         else '[non-json response omitted]'
       end sanitized_body,
       created
from net._http_response
order by created desc
limit 3;
