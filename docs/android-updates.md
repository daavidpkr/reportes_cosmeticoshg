# Publicar una actualización Android

El actualizador consulta exclusivamente la última **GitHub Release pública** de
`daavidpkr/reportes_cosmeticoshg`. La release debe incluir exactamente estos dos
assets subidos y en estado `uploaded`:

- El APK release firmado con la misma clave de la aplicación instalada.
- `update_manifest.json`, con este esquema completo:

```json
{
  "schema_version": 1,
  "title": "Novedades de la versión",
  "version": "1.1.0",
  "build": 8,
  "description": "Resumen breve para el usuario.",
  "mandatory": false,
  "apk": {
    "asset": "cosmeticos-hg-8.apk",
    "size": 12345678,
    "sha256": "64 caracteres hexadecimales en minúsculas"
  }
}
```

Antes de publicar:

1. Aumentar `version` y el número después de `+` en `pubspec.yaml`. El `build`
   del manifiesto debe ser ese mismo número y debe superar al ya instalado.
2. Firmar el APK con la clave release histórica. No cambiar `applicationId`.
3. Obtener el tamaño exacto en bytes y el SHA-256 del APK ya firmado; no volver
   a modificarlo después.
4. Usar un nombre de asset simple, terminado en `.apk`, y copiarlo de forma
   idéntica en `apk.asset`.
5. Elegir `mandatory: true` solo cuando sea imprescindible impedir el uso de
   versiones anteriores. Un fallo de red sigue ofreciendo **Reintentar**.
6. Crear la GitHub Release como pública (no borrador ni prerelease) y adjuntar
   ambos archivos. Comprobar que sea la release marcada como `latest`.

La app no confía solo en el manifiesto: contrasta el asset con la release,
descarga a la caché privada con nombre seguro y verifica tamaño, SHA-256,
paquete, versión, build y firma antes de abrir el instalador Android. La versión
recién instalada elimina al iniciar los APK anteriores que ya no necesita.
