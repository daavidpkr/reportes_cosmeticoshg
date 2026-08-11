import json
import os
import uuid

import psycopg
from psycopg.rows import dict_row


def new_id():
    return str(uuid.uuid4())


connection = psycopg.connect(
    host=os.environ["PGHOST"],
    port=os.environ["PGPORT"],
    user=os.environ["PGUSER"],
    password=os.environ["PGPASSWORD"],
    dbname=os.environ["PGDATABASE"],
    sslmode="require",
    row_factory=dict_row,
)
output = {}

with connection.cursor() as cursor:
    cursor.execute("set role postgres")
    cursor.execute(
        "select user_id::text uid, organization_id::text org "
        "from public.organization_members where active"
    )
    context = cursor.fetchone()
    user_id, organization_id = context["uid"], context["org"]
connection.rollback()

try:
    with connection.cursor() as cursor:
        cursor.execute("begin")
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )

        monthly_request = new_id()
        cursor.execute(
            "select public.enterprise_save_monthly_report(%s,2099,12) id",
            (monthly_request,),
        )
        monthly_id = cursor.fetchone()["id"]
        cursor.execute(
            "select public.enterprise_save_monthly_report(%s,2099,12) id",
            (monthly_request,),
        )
        monthly_id_retry = cursor.fetchone()["id"]

        seller_request = new_id()
        cursor.execute(
            "select public.enterprise_save_seller(%s,null,'ZZR','Synthetic') ok",
            (seller_request,),
        )
        seller_saved = cursor.fetchone()["ok"]

        invoice_request = new_id()
        invoice_params = (
            invoice_request,
            "RPC-ROLLBACK",
            "Synthetic RPC",
            "Synthetic RPC",
            "2026-08-10",
            "N/A",
            10,
        )
        cursor.execute(
            "select public.enterprise_upsert_invoice(%s,%s,%s,%s,%s,%s,%s) result",
            invoice_params,
        )
        invoice_result = cursor.fetchone()["result"]
        cursor.execute(
            "select public.enterprise_upsert_invoice(%s,%s,%s,%s,%s,%s,%s) result",
            invoice_params,
        )
        invoice_result_retry = cursor.fetchone()["result"]

        cursor.execute(
            "select public.enterprise_save_report_row(%s,999990,'2099-12',"
            "'RPC-ROLLBACK','Synthetic RPC','Synthetic RPC','2026-08-10',"
            "10,'ZZR',0,'[]'::jsonb,'[]'::jsonb)",
            (new_id(),),
        )
        cursor.execute(
            "select public.enterprise_save_payment_reminder("
            "%s,'RPC-ROLLBACK','2026-08-14',true,true,true) id",
            (new_id(),),
        )
        reminder_id = str(cursor.fetchone()["id"])
        cursor.execute(
            "select payment_date,schedule_version::text version "
            "from public.payment_reminders where id=%s",
            (reminder_id,),
        )
        before = cursor.fetchone()

        cursor.execute("set local role postgres")
        cursor.execute(
            "insert into public.payment_notification_events("
            "organization_id,reminder_id,schedule_version,notice_type,"
            "scheduled_for,status) select %s,id,schedule_version,'one_day',"
            "'2026-08-13','pending' from public.payment_reminders where id=%s "
            "returning id::text",
            (organization_id, reminder_id),
        )
        event_id = cursor.fetchone()["id"]
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )

        comment_request = new_id()
        cursor.execute(
            "select * from public.add_payment_followup(%s,%s,'comment only',null)",
            (reminder_id, comment_request),
        )
        comment = cursor.fetchone()
        cursor.execute(
            "select * from public.add_payment_followup(%s,%s,'comment only',null)",
            (reminder_id, comment_request),
        )
        comment_retry = cursor.fetchone()
        cursor.execute(
            "select payment_date,schedule_version::text version "
            "from public.payment_reminders where id=%s",
            (reminder_id,),
        )
        after_comment = cursor.fetchone()

        cursor.execute(
            "select * from public.add_payment_followup(%s,%s,null,'2026-08-15')",
            (reminder_id, new_id()),
        )
        cursor.execute(
            "select payment_date,schedule_version::text version "
            "from public.payment_reminders where id=%s",
            (reminder_id,),
        )
        after_reschedule = cursor.fetchone()
        cursor.execute("set local role postgres")
        cursor.execute(
            "select status from public.payment_notification_events where id=%s",
            (event_id,),
        )
        event_status = cursor.fetchone()["status"]
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )
        cursor.execute(
            "select count(*) n from public.payment_followups where reminder_id=%s",
            (reminder_id,),
        )
        followup_count = cursor.fetchone()["n"]
        cursor.execute("set local role postgres")
        cursor.execute(
            "select count(*) n from public.enterprise_requests "
            "where organization_id=%s and request_id=%s",
            (organization_id, invoice_request),
        )
        invoice_request_count = cursor.fetchone()["n"]

        output["business"] = {
            "monthly_idempotent": monthly_id == monthly_id_retry,
            "seller_saved": seller_saved,
            "invoice_idempotent": invoice_result == invoice_result_retry,
            "comment_idempotent": comment == comment_retry,
            "comment_kept_date": before["payment_date"]
            == after_comment["payment_date"],
            "comment_kept_version": before["version"]
            == after_comment["version"],
            "weekend_to_monday": str(after_reschedule["payment_date"])
            == "2026-08-17",
            "reschedule_changed_version": before["version"]
            != after_reschedule["version"],
            "stale_event_cancelled": event_status == "cancelled",
            "followup_count": followup_count,
            "invoice_request_count": invoice_request_count,
        }

        cursor.execute("set local role postgres")
        other_organization = new_id()
        cursor.execute(
            "insert into public.organizations(id,name) values(%s,'Other Rollback Org')",
            (other_organization,),
        )
        cursor.execute("set local session_replication_role='replica'")
        cursor.execute(
            "insert into public.facturas_maestras(organization_id,ref_fact,cliente,"
            "nombre_comercial,fecha,nro_fact,venta) values("
            "%s,'OTHER-ROLLBACK','Other','Other','2026-08-10','N/A',0)",
            (other_organization,),
        )
        cursor.execute("set local session_replication_role='origin'")
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )
        cursor.execute("savepoint isolate")
        try:
            cursor.execute(
                "select public.enterprise_upsert_invoice("
                "%s,'OTHER-ROLLBACK','Changed','Changed','2026-08-10','N/A',0)",
                (new_id(),),
            )
            output["cross_org_rejected"] = False
        except psycopg.Error:
            cursor.execute("rollback to savepoint isolate")
            output["cross_org_rejected"] = True

        cursor.execute("set local role postgres")
        cursor.execute("set local session_replication_role='replica'")
        cursor.execute(
            "insert into public.reportes_ventas(organization_id,id,nro_fila,"
            "ref_fact,vendedor,mes_reporte) values("
            "%s,999999992,777777,'OTHER-ROLLBACK','X','OTHER-MONTH')",
            (other_organization,),
        )
        cursor.execute("set local session_replication_role='origin'")
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )
        cursor.execute("savepoint atomic")
        try:
            cursor.execute(
                "select public.enterprise_save_report_row("
                "%s,777777,'OTHER-MONTH','ATOMIC-ROLLBACK','Atomic','Atomic',"
                "'2026-08-10',1,'ZZR',0,'[]','[]')",
                (new_id(),),
            )
            output["atomic_error"] = False
        except psycopg.Error:
            cursor.execute("rollback to savepoint atomic")
            output["atomic_error"] = True
        cursor.execute(
            "select count(*) n from public.facturas_maestras "
            "where ref_fact='ATOMIC-ROLLBACK'"
        )
        output["atomic_no_partial"] = cursor.fetchone()["n"] == 0

        cursor.execute("set local role postgres")
        cursor.execute("savepoint inactive")
        cursor.execute(
            "update public.organization_members set active=false where user_id=%s",
            (user_id,),
        )
        cursor.execute("set local role authenticated")
        cursor.execute(
            "select set_config('request.jwt.claim.sub',%s,true)", (user_id,)
        )
        try:
            cursor.execute(
                "select public.enterprise_save_monthly_report(%s,2098,1)",
                (new_id(),),
            )
            output["inactive_rejected"] = False
        except psycopg.Error:
            cursor.execute("rollback to savepoint inactive")
            output["inactive_rejected"] = True

        cursor.execute("set local role anon")
        try:
            cursor.execute(
                "select public.enterprise_save_monthly_report(%s,2098,2)",
                (new_id(),),
            )
            output["anon_rejected"] = False
        except psycopg.Error:
            output["anon_rejected"] = True
finally:
    connection.rollback()

with connection.cursor() as cursor:
    cursor.execute("set role postgres")
    cursor.execute("begin read only")
    cursor.execute(
        "select "
        "(select count(*) from public.facturas_maestras "
        " where ref_fact like '%ROLLBACK%') invoices,"
        "(select count(*) from public.reportes_mensuales where anio>=2098) reports,"
        "(select count(*) from public.vendedores where codigo='ZZR') sellers,"
        "(select count(*) from public.enterprise_requests "
        " where created_at>clock_timestamp()-interval '10 minutes') requests"
    )
    output["persistent_synthetic"] = cursor.fetchone()
    cursor.execute("rollback")

connection.close()
print(json.dumps(output, default=str, ensure_ascii=False))
