# Distribución Android externa

## Firma y actualizaciones

La aplicación usa `com.example.reportes_cosmeticoshg`. Las actualizaciones deben
conservar ese `applicationId` y la misma clave release, y aumentar siempre el
`versionCode`. El keystore y `key.properties` permanecen fuera de Git y deben
mantener una copia de seguridad protegida. Perder la clave impide publicar una
actualización instalable sobre las versiones actuales.

Antes de entregar un APK release, verificarlo con `apksigner verify --verbose
--print-certs` y comparar la huella SHA-256 pública con la registrada. No publicar
el APK, el keystore, contraseñas ni claves privadas en el repositorio.

## Google Play Protect

El aviso "Play Protect hasn't seen an app from this developer before" indica una
aplicación o un desarrollador todavía desconocido para el análisis de Google; no
es, por sí solo, una detección de malware ni un error de firma. La aplicación no
puede suprimirlo y no se debe pedir a los usuarios que desactiven Play Protect.

Para distribución exclusivamente externa, el propietario puede usar
[Android Developer Console](https://support.google.com/android-developer-console/answer/16604405)
para verificar su identidad y registrar el nombre de paquete y claves de firma.
Si ya usa Play Console, puede registrar allí también aplicaciones distribuidas
fuera de Google Play. La distribución limitada anunciada por Google admite hasta
20 dispositivos sin tarifa; la distribución completa requiere las condiciones y
el pago indicados por Google. Este registro no publica la aplicación ni garantiza
que desaparezca inmediatamente cualquier advertencia.

Si Play Protect clasifica o bloquea incorrectamente un APK ya firmado y auditado,
usar el formulario oficial de
[verificación y apelación](https://support.google.com/googleplay/android-developer/answer/2992033).
La identidad, aceptación de términos, pagos y envío de una apelación requieren
una decisión expresa del propietario.

## Prueba visual de notificaciones

Después de crear una release autorizada:

1. Confirmar que el `versionCode` supera al instalado y verificar su certificado.
2. Instalarla como actualización, sin desinstalar, para comprobar continuidad de firma.
3. Forzar cierre, abrir la app, iniciar sesión y confirmar el registro FCM.
4. Probar foreground, segundo plano y app cerrada en MIUI.
5. Revisar vista contraída, expandida, pantalla bloqueada y temas claro/oscuro.
6. Tocar el aviso y confirmar la fecha del Calendario de cobros.

MIUI puede aplicar tintes, fondos o máscaras propios. El icono pequeño será una
silueta monocromática; Android no garantiza mostrar el launcher a color en ese
espacio.
