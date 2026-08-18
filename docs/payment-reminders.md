# Notificaciones de cobros

## Configuración canónica

- Zona empresarial: `America/Guayaquil`.
- Hora visible: `05:00` Ecuador.
- Cron UTC: `0 10 * * *`.
- Arquitectura: Supabase Cron → `process-payment-reminders` → FCM → Android.
- Flutter no programa entregas: solicita permiso, registra el token, recibe FCM y abre el calendario.

## Regla empresarial

La fuente canónica es `payment_reminders.payment_date`, el mismo campo usado por
el Calendario de cobros. Solo se incluyen facturas cuya fecha coincide con el día
actual en Ecuador, con recordatorio activo y saldo canónico superior a `0.005`.
Facturas anteriores, futuras, pagadas, anuladas, huérfanas o pertenecientes a una
organización inactiva quedan excluidas.

La entrega se consolida por organización y dispositivo. Una restricción única
impide más de una entrega empresarial por usuario, dispositivo, fecha local y
tipo, aunque el Cron sea reintentado o ejecutado concurrentemente.

## Programación segura

La migración crea exactamente el trabajo `process-same-day-payment-reminders` y
elimina únicamente trabajos cuyo nombre o comando invoca inequívocamente la misma
Edge Function. La credencial de invocación se genera dentro de Vault y nunca se
incorpora al repositorio ni a la salida del CLI.

## Comportamiento después de las 05:00

Una factura programada o reprogramada para el mismo día después de las 05:00
permanece visible en el calendario, pero no genera una entrega inmediata. Se
mantiene una sola ejecución diaria; actualizar la aplicación no envía avisos.

## Plataforma

La entrega remota está soportada en Android. Web y Windows no están habilitados
por esta arquitectura.
