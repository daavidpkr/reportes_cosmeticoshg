-- Solo lectura. Ejecutar antes y después de la migración correctiva.

-- Privilegios efectivos de ejecución esperados:
-- anon=false, authenticated=true, service_role=true.
select
  roles.role_name,
  p.oid::regprocedure::text as signature,
  has_function_privilege(roles.role_name, p.oid, 'EXECUTE') as can_execute
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
cross join unnest(array['anon', 'authenticated', 'service_role'])
  as roles(role_name)
where n.nspname = 'public'
  and p.proname in ('register_fcm_device', 'deactivate_fcm_device')
order by signature, role_name;

-- ACL explícita de las funciones. Permite detectar concesiones a PUBLIC.
select
  p.oid::regprocedure::text as signature,
  coalesce(grantee.rolname, 'PUBLIC') as grantee,
  privileges.privilege_type,
  privileges.is_grantable
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner)))
  as acl
join lateral (
  values (
    case acl.privilege_type when 'X' then 'EXECUTE' else acl.privilege_type::text end,
    acl.is_grantable
  )
) as privileges(privilege_type, is_grantable) on true
left join pg_catalog.pg_roles grantee on grantee.oid = acl.grantee
where n.nspname = 'public'
  and p.proname in ('register_fcm_device', 'deactivate_fcm_device')
order by signature, grantee;

-- Privilegio DELETE efectivo esperado para service_role: false.
select
  has_table_privilege(
    'service_role',
    'public.payment_notification_events',
    'DELETE'
  ) as service_role_can_delete;

-- ACL directa de la tabla. Identifica si DELETE procede de PUBLIC o de otro rol.
select
  coalesce(grantee.rolname, 'PUBLIC') as grantee,
  case acl.privilege_type
    when 'r' then 'SELECT'
    when 'a' then 'INSERT'
    when 'w' then 'UPDATE'
    when 'd' then 'DELETE'
    when 'D' then 'TRUNCATE'
    when 'x' then 'REFERENCES'
    when 't' then 'TRIGGER'
    else acl.privilege_type::text
  end as privilege_type,
  acl.is_grantable
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner)))
  as acl
left join pg_catalog.pg_roles grantee on grantee.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'payment_notification_events'
order by grantee, privilege_type;

-- Propietario e herencia transitiva de service_role.
with recursive inherited_roles as (
  select member.oid as member_oid, member.rolname as member_name,
         parent.oid as inherited_oid, parent.rolname as inherited_role
  from pg_catalog.pg_auth_members membership
  join pg_catalog.pg_roles member on member.oid = membership.member
  join pg_catalog.pg_roles parent on parent.oid = membership.roleid
  where member.rolname = 'service_role'

  union all

  select inherited.member_oid, inherited.member_name,
         parent.oid, parent.rolname
  from inherited_roles inherited
  join pg_catalog.pg_auth_members membership
    on membership.member = inherited.inherited_oid
  join pg_catalog.pg_roles parent on parent.oid = membership.roleid
)
select 'table_owner' as source,
       owner.rolname as role_name,
       (owner.rolname = 'service_role')::text as detail
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
join pg_catalog.pg_roles owner on owner.oid = c.relowner
where n.nspname = 'public'
  and c.relname = 'payment_notification_events'

union all

select 'inherited_role', inherited_role, 'service_role inherits this role'
from inherited_roles
order by source, role_name;
