# Reconciliación controlada del historial de migraciones

Fecha de auditoría: 2026-08-10 (America/Guayaquil)

Estado: propuesta local. Ningún comando de reparación ni migración fue ejecutado.

## Diagnóstico del mecanismo

- Supabase CLI usada para el diagnóstico: `2.113.0` mediante `npx` (no hay binario global instalado).
- PostgreSQL remoto informado por el proyecto enlazado: `17.6.1.155`.
- PostgREST remoto: `v14.15`.
- GoTrue remoto: `v2.195.0`.
- `supabase migration list --linked` no devuelve versiones remotas.
- Una consulta de catálogo de solo lectura confirmó que no existe un esquema cuyo nombre comience por `supabase_migrations`; por tanto no es una diferencia de nombre de tabla conocida por esta versión de CLI.
- `supabase db push --linked --dry-run` considera pendientes las diez migraciones que permanecen en `supabase/migrations`.
- Los objetos de las cuatro migraciones históricas sí están materializados. La explicación más probable es que el SQL se ejecutó directamente mediante SQL Editor, Dashboard, script o una operación equivalente que no registró versiones en el historial de la CLI. El catálogo no conserva evidencia suficiente para distinguir cuál de esos canales fue utilizado.
- El repositorio contiene evidencia operacional de despliegues controlados anteriores y el estado remoto coincide con sus efectos acumulados. No se encontró evidencia de que se usara previamente `supabase db push`.

## Estado histórico y ausencia de cambios empresariales

La auditoría remota de solo lectura confirmó:

| Objeto | Filas |
|---|---:|
| `facturas_maestras` | 15 |
| `reportes_ventas` | 15 |
| `reportes_mensuales` | 1 |
| `vendedores` | 2 |
| `fcm_devices` | 1 |
| `payment_reminders` | 0 |
| `payment_followups` | 0 |
| `payment_notification_events` | 0 |
| `auth.users` | 1 |

No existen `organizations`, `organization_members`, `billing_customers`, `invoice_payment_terms` ni `enterprise_requests`. Tampoco existen las funciones empresariales, columnas `organization_id` o triggers de compatibilidad. No hay organización, membresía ni backfill.

## Inventario completo

| Versión | Archivo y propósito | Objetos/dependencias | Datos o destrucción | Reejecución | Estado y clasificación |
|---|---|---|---|---|---|
| `20260810130000` | `payment_reminders.sql`: recordatorios, dispositivos y eventos FCM | Crea tres tablas, índices, trigger, cuatro funciones, RLS y políticas. Depende de `auth.users`, `facturas_maestras(ref_fact)`, `auth.uid()` y `gen_random_uuid()` | No transforma datos. Revoca y concede permisos solamente sobre objetos nuevos | No segura: `CREATE TABLE/FUNCTION/POLICY` sin `IF NOT EXISTS` | Histórica materializada; **Coincidencia completa acumulativa** |
| `20260810140000` | `fix_payment_reminders_privileges.sql`: corrige ejecución de RPC FCM y elimina `DELETE` de eventos para `service_role` | Depende de las funciones y tabla de `130000` | Solo ACL; no datos | Semánticamente repetible | Histórica materializada; **Coincidencia completa** |
| `20260810150000` | `payment_followups.sql`: historial/idempotencia de seguimientos y ajuste de fin de semana | Crea `next_weekday`, `payment_followups`, índices y RPC; amplía estado de eventos y reemplaza trigger | No transforma filas históricas; reemplaza una restricción y trigger | No segura por creación de objetos existentes | Histórica materializada; **Coincidencia completa acumulativa** |
| `20260810151000` | `fix_payment_followups_created_at.sql`: fija `created_at` a `clock_timestamp()` | Depende de `payment_followups` | Solo metadato de default; no actualiza filas | Segura y repetible | Histórica materializada; **Coincidencia completa**, sustentada por el registro operacional previo y el default remoto. El catálogo aislado no permite atribuir causalidad porque el archivo local `150000` ya contiene el mismo default |
| `20260810160100` | `organization_foundation.sql`: organizaciones, membresías y resolución de organización | Crea tablas, índices, dos funciones, RLS/ACL; depende de `auth.users` | No crea filas de organización ni membresía | No segura | Empresarial; **No aplicada**; autorizable solo en fase remota correspondiente |
| `20260810160200` | `enterprise_columns_and_customers.sql`: columnas organizacionales, clientes y plazos | Modifica ocho tablas; crea dos tablas, función, índices y políticas; depende de `60100` y de tablas históricas | No hace backfill; agrega columnas nulas y metadatos | No segura | Empresarial; **No aplicada** |
| `20260810160300` | `enterprise_invoice_rpcs.sql`: idempotencia, facturas, clientes, plazos y excepciones | Crea tabla y cinco RPC públicas más auxiliares; depende de `60100`, `60200`, `next_weekday` y objetos de cobros | No ejecuta RPC ni cambia datos por sí sola | No segura | Empresarial; **No aplicada** |
| `20260810160325` | `enterprise_legacy_compatibility.sql`: triggers transitorios para la aplicación heredada | Crea/reemplaza funciones trigger e instala triggers; depende de organización, membresía y backfill | Puede asignar organización en escrituras futuras; no backfill directo | No segura | **No aplicada y prohibida en la fase actual** |
| `20260810160350` | `enterprise_business_rpcs.sql`: RPC restantes y reemplazos empresariales | Crea/reemplaza RPC para reportes, vendedores, cobros, recordatorios y FCM; depende de fases anteriores | No invoca las RPC ni transforma datos al instalarse | No segura | **No aplicada y prohibida en la fase actual** |
| `20260810160400` | `enterprise_security_cutover.sql`: corte final de seguridad | Valida ausencia de nulos, impone `NOT NULL`, elimina políticas permisivas, crea políticas empresariales y revoca escrituras directas | No elimina datos, pero es destructiva respecto del acceso vigente | No segura | **No aplicada y prohibida en la fase actual** |
| `20260810160000` | `customer_payment_terms.sql`: diseño anterior retirado | Archivo ubicado en `docs/not-applicable`, fuera de `supabase/migrations` | No debe ejecutarse | No corresponde | **No aplicable**; nunca registrar como aplicada |

## Matriz de evidencia semántica histórica

| Versión | Evidencia remota | Diferencias explicadas por migraciones posteriores | Resultado |
|---|---|---|---|
| `130000` | Las tres tablas existen con columnas, tipos, nulabilidad, defaults, PK/FK/checks e índices esperados. RLS está activo. Las cinco políticas esperadas coinciden. Las cuatro funciones tienen argumentos, retornos, cuerpo, propietario `postgres`, volatilidad, `SECURITY DEFINER/INVOKER` y `search_path=''` esperados | El trigger ahora cubre `INSERT,UPDATE` y el estado admite `cancelled`, ambos cambios de `150000`. Los ACL finales incluyen los ajustes de `140000` y privilegios directos de `service_role` derivados de los defaults de la plataforma | Coincidencia completa acumulativa |
| `140000` | `register_fcm_device` y `deactivate_fcm_device` son ejecutables por `authenticated` y `service_role`, no por `anon/PUBLIC`. `payment_notification_events` no concede `DELETE` a `service_role` | Ninguna | Coincidencia completa |
| `150000` | `payment_followups` coincide en columnas, defaults, FK/check/unique e índices; RLS y política de lectura coinciden. `next_weekday` y `add_payment_followup` coinciden íntegramente. El trigger remoto es `BEFORE INSERT OR UPDATE`. El check de eventos incluye `cancelled` | Ninguna material | Coincidencia completa acumulativa |
| `151000` | `payment_followups.created_at` tiene exactamente `clock_timestamp()` | El mismo default también aparece ya en la copia local actual de `150000`; la ejecución individual no es demostrable solo con catálogo. Se conserva como evidencia adicional el registro operacional previo | Coincidencia completa con salvedad de atribución |

No hay secuencias de identidad ni vistas creadas por estas migraciones. `pgcrypto 1.3` y `uuid-ossp 1.1` están instaladas en `extensions`. Ninguna de las cuatro tablas de cobros está añadida a una publicación Realtime. Las migraciones históricas no contienen seeds ni transformaciones de datos.

No se requiere una migración correctiva: no se halló diferencia material entre el estado acumulado esperado y el remoto.

## Plan de reconciliación propuesto

Solo estas versiones cumplen la condición para ser marcadas como aplicadas:

1. `20260810130000`
2. `20260810140000`
3. `20260810150000`
4. `20260810151000`

Comando oficial propuesto, todavía **no ejecutado**:

```powershell
npx --yes supabase@2.113.0 migration repair --linked --status applied 20260810130000 20260810140000 20260810150000 20260810151000
```

La sintaxis fue confirmada con `supabase migration repair --help` de CLI `2.113.0`. Este comando no abre ni ejecuta el SQL de los archivos: actualiza únicamente el historial remoto que consulta la CLI. Dado que el esquema de historial está ausente, la herramienta oficial deberá crearlo como parte de su mecanismo; si la herramienta falla o propone una operación distinta, se debe detener sin crear la tabla manualmente.

Verificación propuesta:

```powershell
npx --yes supabase@2.113.0 migration list --linked
npx --yes supabase@2.113.0 db push --linked --dry-run
```

No ejecutar `db push` real. La simulación solo sirve para verificar pendientes.

Resultado esperado de `migration list`: las cuatro versiones históricas aparecen tanto local como remotamente; `60100`, `60200`, `60300`, `60325`, `60350` y `60400` permanecen solo locales.

Resultado esperado de `db push --dry-run`: muestra únicamente:

```text
20260810160100_organization_foundation.sql
20260810160200_enterprise_columns_and_customers.sql
20260810160300_enterprise_invoice_rpcs.sql
20260810160325_enterprise_legacy_compatibility.sql
20260810160350_enterprise_business_rpcs.sql
20260810160400_enterprise_security_cutover.sql
```

Que `60325`, `60350` y `60400` aparezcan como pendientes no las autoriza. La CLI representa orden cronológico, no permisos de despliegue. `20260810160000_customer_payment_terms.sql` no debe aparecer porque está fuera de `supabase/migrations`.

## Reversión exclusiva del historial

Si una versión se marca incorrectamente, usar únicamente para esa versión:

```powershell
npx --yes supabase@2.113.0 migration repair --linked --status reverted VERSION_INCORRECTA
```

Después repetir `migration list --linked`. Esta reversión solo cambia el historial; no revierte ni ejecuta DDL. No usar `db reset`, `db push`, SQL manual ni restauraciones para corregir un error de historial.

## Riesgos y detenciones

- El canal exacto del despliegue histórico no puede probarse desde PostgreSQL; SQL Editor/ejecución directa es la causa más probable.
- La versión `151000` comparte su único efecto con el estado actual del archivo `150000`; por ello su evidencia combina estado remoto y registro operacional, no causalidad catalogable.
- Ejecutar `db push` antes de reparar intentaría aplicar diez archivos, incluidos los prohibidos.
- Reparar una versión sin coincidencia completa ocultaría una divergencia y queda excluido del plan.
- Tras la reparación debe revisarse que el mecanismo oficial haya creado solo sus objetos internos de historial y cuatro filas, sin DDL empresarial.

