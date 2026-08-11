# Despliegue empresarial de Cosméticos HG — 2026-08-10

Estado: completado.

## Base de datos

- Historial reconciliado y migraciones `20260810130000` a
  `20260810160400` aplicadas una sola vez.
- Organización `Cosméticos HG` creada con una membresía administrativa activa.
- Backfill: 15 facturas, 15 filas de reporte, 1 reporte mensual, 2 vendedores y
  1 dispositivo FCM asignados a una sola organización.
- Catálogo de clientes: 13 identidades normalizadas y 15 vínculos de factura.
- Cero `organization_id` nulos, huérfanos, duplicados o datos sintéticos.
- Triggers de compatibilidad heredada retirados durante el corte.
- Tablas operativas: acceso directo de `authenticated` limitado a `SELECT` con
  RLS organizacional; escrituras mediante RPC `SECURITY DEFINER` autenticadas.

## Verificación

- RPC: idempotencia, atomicidad, aislamiento, fin de semana, seguimiento,
  reprogramación y cancelación stale aprobados dentro de transacciones con
  `ROLLBACK`.
- `anon`, miembros inactivos y acceso entre organizaciones rechazados.
- Edge Function `process-payment-reminders` versión 4 desplegada.
- Cron activo en `*/10 * * * *`; primera ejecución posterior al despliegue:
  exitosa, HTTP 200, sin eventos pendientes.
- Flutter: análisis sin incidencias, 28 pruebas aprobadas y builds release web y
  Android generados con versión `1.0.0+4`.

## Operación

- No volver a instalar `20260810160325_enterprise_legacy_compatibility.sql`.
- Incorporar usuarios únicamente mediante una operación administrativa auditada
  sobre `organization_members`.
- Antes de incorporar una segunda empresa, sustituir las claves globales
  `ref_fact`, identificador mensual y código de vendedor por claves internas o
  restricciones compuestas por organización.
- Conservar el respaldo previo fuera del repositorio y no publicar APK o web sin
  un flujo de distribución explícito.
