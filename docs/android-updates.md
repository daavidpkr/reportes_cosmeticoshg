# Publicar una actualización Android

La publicación Android es independiente del despliegue normal de GitHub Pages.
Solo se ejecuta manualmente desde **Actions → Publicar actualización Android →
Run workflow**, sobre la rama `main`. El workflow compila el APK release,
verifica su firma, calcula el SHA-256, genera `update_manifest.json` desde
`release/android/update_manifest.v1.template.json` y publica ambos assets en
una GitHub Release marcada como `latest`.

## Configuración única

Crear el environment protegido `android-release` (se recomienda aprobación
manual) y configurar estos GitHub Secrets:

- `ANDROID_KEYSTORE_BASE64`: keystore release completo codificado en Base64.
- `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` y `ANDROID_STORE_PASSWORD`.
- `ANDROID_CERT_SHA256`: huella SHA-256 del certificado release esperado.

Nunca subir el keystore, `key.properties` ni contraseñas. El workflow usa un
keystore temporal y lo elimina siempre. Si falta un secret, la firma no es
válida, el certificado no coincide o faltan metadatos/assets, la ejecución se
detiene antes de publicar.

## Antes de ejecutar

1. Actualizar `version: x.y.z+build` en `pubspec.yaml`; ambos valores deben ser
   superiores a los ya publicados.
2. Confirmar los cambios en `main`. La entrada **version** debe coincidir
   exactamente con `x.y.z`; el build se obtiene únicamente de `pubspec.yaml`.
3. Completar título y descripción. El workflow rechaza valores vacíos.

Para una actualización **opcional**, usar `mandatory: false`. Para una
actualización **obligatoria**, usar `mandatory: true` y establecer
`minimum_supported_version` en la primera versión que seguirá admitida. Para
obligar a todas las versiones anteriores, usar como mínima la nueva versión.
La aplicación nunca infiere la obligatoriedad solo por el build.

El workflow primero crea una release borrador, comprueba que contenga
exactamente el APK firmado y `update_manifest.json`, y solo entonces la hace
pública. No debe ejecutarse para ensayos: al completarse publica una release
real. La publicación web continúa usando exclusivamente `static.yml` y no
genera APK ni releases.
