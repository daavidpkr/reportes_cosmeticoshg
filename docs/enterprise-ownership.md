# Modelo empresarial preparado (no desplegado)

## Auditoría sanitizada

- Auth: 1 usuario confirmado, con acceso reciente y sin indicador de cuenta técnica/prueba.
- Datos: 15 facturas, 13 identidades exactas de cliente, 15 filas de reporte,
  1 reporte mensual, 2 vendedores y 1 dispositivo.
- Cobros, seguimientos y eventos: 0.
- Integridad: 0 referencias de factura duplicadas y 0 huérfanos detectados.
- La evidencia es compatible con una sola empresa, pero no demuestra por sí sola
  qué usuario debe ser miembro ni autoriza el backfill.

## Tablas empresariales

Requieren `organization_id`: `facturas_maestras`, `reportes_mensuales`,
`reportes_ventas`, `vendedores`, `payment_reminders`, `payment_followups`,
`payment_notification_events`, `billing_customers` e
`invoice_payment_terms`. `fcm_devices` conserva además `user_id`, porque el
token pertenece a un usuario/dispositivo aunque su contexto sea empresarial.

## Membresías

`organizations` representa la empresa. `organization_members` admite una sola
membresía activa por usuario. El alta, revocación y cambio de rol se realiza
administrativamente con `service_role`; Flutter solo puede leer su propia
membresía y nunca envía ni elige una organización.

La cuenta observada debe ser confirmada manualmente como miembro legítimo. No se
crean membresías por registro, inicio de sesión ni coincidencia de correo.

## Migraciones y orden

1. `20260810160100_organization_foundation.sql`: estructura y lectura de
   membresía; no cambia permisos empresariales existentes.
2. `20260810160200_enterprise_columns_and_customers.sql`: columnas nullable,
   catálogo y términos; no asigna filas históricas.
3. `20260810160300_enterprise_invoice_rpcs.sql`: escrituras autenticadas e
   idempotentes sin parámetros de organización.
4. Realizar y verificar un respaldo recuperable.
5. Ejecutar administrativamente `bootstrap_cosmeticos_hg.sql`, que valida los
   conteos auditados, crea la empresa/membresía y hace el backfill en una sola
   transacción.
6. `20260810160325_enterprise_legacy_compatibility.sql`: etiqueta las escrituras
   de 1.0.0+3 durante la transición y rechaza escrituras sin membresía.
7. `20260810160350_enterprise_business_rpcs.sql`: reportes, filas, vendedores,
   FCM, recordatorios y seguimientos empresariales.
8. Adaptar y distribuir Flutter; validar dos miembros y una organización ajena.
9. `20260810160400_enterprise_security_cutover.sql`: revocación de acceso
   público y políticas por membresía. Se autoaborta si quedan filas sin empresa.
10. Activar clientes/plazos y generar APK solo tras las pruebas integrales.

## Ventana de transición

La estructura aditiva puede convivir con 1.0.0+3, pero durante esa convivencia
las políticas públicas antiguas siguen siendo el riesgo conocido. No debe
crearse una segunda empresa ni considerarse seguro el aislamiento hasta el
corte. Para acortar la ventana: preparar y probar RPC/app en un entorno de
prueba, respaldar, ejecutar backfill, distribuir la app compatible y aplicar el
corte en una ventana coordinada. Si la app compatible no está instalada, el
corte se pospone; nunca se relajan simultáneamente políticas nuevas y antiguas.

## Claves globales pendientes

`ref_fact`, el id mensual y el código de vendedor son actualmente globales. El
modelo preparado mantiene esa compatibilidad durante la transición. Antes de
incorporar una segunda empresa que pueda repetir esos valores se requiere una
migración de claves: identificador interno estable de factura y unicidad
`(organization_id, ref_fact)`, propagada a reportes, términos y recordatorios.
No debe habilitarse una segunda empresa hasta decidir y probar ese corte.

## Backfill

No se ejecuta automáticamente. El template asigna una organización solo después
de respaldo, autorización y verificación de conteos/huellas. Propaga la empresa
desde factura a reportes, recordatorios, seguimientos y eventos. Toda la plantilla
termina en `ROLLBACK` y sus sentencias permanecen comentadas.

## Flutter pendiente antes del corte

- Las escrituras directas de facturas, reportes mensuales, filas, vendedores y
  recordatorios ya fueron sustituidas localmente por RPC empresariales.
- Las lecturas y streams permanecen directos y quedan filtrados por RLS.
- No enviar `organization_id` desde Flutter.
- Mantener `request_id` estable durante reintentos de red.
- Mostrar sesión sin membresía como acceso empresarial no autorizado.
- Usar Realtime/refresh sobre tablas filtradas por RLS para sincronización.

## Decisiones pendientes

- Definir quién operará administrativamente futuras altas y revocaciones.
- Elegir la estrategia definitiva de claves antes de una segunda organización.

## Respaldo y reversión

Antes del bootstrap se requiere un backup verificable del proyecto (backup/PITR
de Supabase o `supabase db dump` con credenciales administrativas), más conteos
y huellas de las tablas empresariales. El backup debe restaurarse primero en un
entorno aislado para confirmar que es recuperable.

La reversión preferida es restaurar ese backup si falla el backfill o el corte.
Antes del corte, las migraciones son aditivas y la app 1.0.0+3 sigue operativa;
puede posponerse el avance sin borrar columnas. Después del corte no se deben
eliminar datos ni columnas manualmente: se restaura el backup o se aplica una
migración forward revisada. Reabrir las políticas `public using(true)` solo se
contempla como emergencia temporal porque vuelve a exponer datos.
