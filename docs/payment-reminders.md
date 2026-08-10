# Recordatorios de pago: despliegue pendiente

Todo lo descrito aquí está preparado localmente. No se ha aplicado ninguna migración, función, secreto ni Cron al proyecto remoto.

## Orden de revisión y despliegue

1. Revisar `supabase/migrations/20260810130000_payment_reminders.sql` y confirmar que `facturas_maestras.ref_fact` es `text` y tiene una restricción única o clave primaria. La aplicación usa actualmente `onConflict: ref_fact`, pero la definición remota no pudo consultarse con la clave pública.
2. Aplicar la migración en un entorno de prueba. No usar `supabase db reset` contra un proyecto remoto.
3. Crear una cuenta de servicio de Firebase con el privilegio mínimo necesario para enviar mensajes FCM. No descargarla ni generarla hasta contar con autorización administrativa.
4. Cargar los secretos en Supabase, sin incorporarlos al repositorio:

   - `FIREBASE_PROJECT_ID=cosmeticoshg-reportes`
   - `FIREBASE_SERVICE_ACCOUNT_JSON` con el JSON completo como valor secreto
   - `CRON_SECRET` con un valor aleatorio largo

   `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` se suministran al entorno de Edge Functions. Nunca se incluyen en Flutter.

5. Desplegar `process-payment-reminders` y probarla manualmente con el encabezado `Authorization: Bearer <CRON_SECRET>`.
6. Solo después de validar el envío real, crear el Cron remoto.

## Programación propuesta

Supabase Cron usa UTC. Para ejecutar a las 08:00 de `America/Guayaquil` (UTC-5), la expresión es:

```cron
0 13 * * *
```

La llamada programada debe obtener el secreto desde Supabase Vault. No debe escribirse el secreto literal en SQL versionado. Un ejemplo conceptual, que debe adaptarse desde el panel remoto después de confirmar los nombres disponibles de Vault, es invocar `pg_net.http_post` hacia la URL de la función con `Authorization: Bearer <valor recuperado de Vault>`.

## Reglas de fecha e idempotencia

- Solo se seleccionan pagos cuya fecha sea exactamente hoy + 3 o hoy + 1 en `America/Guayaquil`.
- No se envían avisos retroactivos, vencidos ni para el propio día del pago.
- Cambiar `payment_date` genera un `schedule_version` nuevo; los avisos futuros pertenecen a la fecha nueva.
- Desactivar impide el envío. Reactivar conserva la versión: un aviso ya enviado no se repite.
- La función administrativa reclama atómicamente cada combinación de recordatorio, versión, aviso y dispositivo.
- El éxito de un dispositivo no se revierte si otro falla. Los fallos temporales se reintentan y los permanentes desactivan solamente el token afectado.
- Si no hay dispositivos se registra `no_devices`, pero no se considera entregado; si aparece un dispositivo mientras todavía corresponde al día del aviso, su evento individual puede enviarse.
- El borrado de una factura elimina sus recordatorios mediante la clave foránea propuesta. Debe confirmarse este comportamiento antes de aplicar la migración.

## Prueba física Android pendiente

Con dos usuarios y, cuando corresponda, dos teléfonos:

1. Probar permiso aceptado, rechazado y apertura de ajustes.
2. Iniciar sesión y comprobar en Supabase que se registra solo un token activo, sin mostrarlo completo en logs.
3. Renovar el token y verificar que la misma sesión queda actualizada.
4. Cerrar sesión y comprobar que solo ese token queda inactivo.
5. Crear pagos a tres días y a un día; ejecutar la función de forma controlada.
6. Repetir la ejecución y confirmar que no hay un segundo mensaje.
7. Probar app abierta, en segundo plano y cerrada, y tocar la notificación.
8. Confirmar que se abre el editor correspondiente a una factura existente y que una factura eliminada muestra un aviso seguro.
9. Probar un token inválido y un fallo temporal, y revisar los eventos por dispositivo.

Una compilación exitosa no sustituye esta prueba ni confirma que FCM esté operativo en producción.
