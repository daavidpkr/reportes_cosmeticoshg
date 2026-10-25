# Versionado y publicacion

Cada conjunto de cambios que llega a `main` debe clasificarse por impacto
funcional, no por cantidad de lineas:

- `patch`: correccion compatible que no agrega una capacidad funcional. Sube
  `x.y.z` a `x.y.(z+1)` y aumenta el build. Publica GitHub Pages, pero no crea
  APK, manifiesto ni GitHub Release.
- `minor`: capacidad nueva compatible o cambio funcional apreciable. Sube a
  `x.(y+1).0`, aumenta el build, publica Pages y ejecuta la publicacion Android.
- `major`: cambio incompatible, migracion que rompe compatibilidad o rediseno
  funcional mayor. Sube a `(x+1).0.0`, aumenta el build y ejecuta el mismo flujo
  Android que `minor`.

El commit publicado debe incluir exactamente un trailer, por ejemplo:

```text
Release-Type: minor
```

Codex debe ejecutar antes del commit:

```text
dart run tool/release_version.dart --bump minor
```

El workflow vuelve a calcular el incremento y rechaza una version incorrecta.
Si `pubspec.yaml` aun no fue incrementado, lo incrementa y crea un unico commit
`chore(release)`. Ese push usa `GITHUB_TOKEN`, no inicia otro workflow y, ademas,
el commit no contiene `Release-Type`; ambas condiciones evitan dobles ejecuciones
y bucles. Pages siempre se construye desde el SHA que ya contiene la version.

## Publicacion Android automatica

`.github/workflows/publish.yml` llama a `android-release.yml` solo para `minor`
o `major`. El workflow conserva la firma y sus validaciones actuales, genera el
APK firmado y `update_manifest.json`, comprueba certificado, hash y assets, crea
un borrador y solo lo publica despues de validar exactamente el APK y el
manifiesto.

El titulo se genera como `Cosmeticos HG x.y.z`. Las notas se forman con todos
los commits desde la ultima release publica cuyo manifiesto sea valido y nombre
un APK subido valido. Por eso los `patch` que no generan APK quedan incluidos en
la siguiente release Android.

Las actualizaciones son opcionales por defecto. No agregue
`Android-Mandatory: true` salvo que el propietario lo solicite explicitamente.
En ese unico caso, el commit debe incluir los dos trailers:

```text
Android-Mandatory: true
Android-Minimum-Version: 2.0.0
```

El workflow falla si se solicita obligatoriedad sin version minima. Nunca debe
inferirse `mandatory=true` por severidad, tipo de version, build ni descripcion.

La lista completa de GitHub Releases es la unica fuente de verdad de la ultima
version Android. La app pagina todas las releases publicas, valida cada candidata
y elige globalmente la mayor version semantica; si dos candidatas tienen la misma
version, gana el `buildNumber` mayor. El orden o fecha de publicacion no decide.
Por ejemplo, una instalacion `1.3.0+12` salta directamente a `1.6.0+16` aunque
tambien existan `1.4.0+13` y `1.5.0+14`.

Solo se considera una release Android cuando contiene exactamente un
`update_manifest.json` y el APK referenciado, ambos subidos; el tag coincide con
`android-v<version>-<build>` y el digest SHA-256 del asset coincide con el
manifiesto. Se ignoran borradores, prereleases, manifiestos malformados, assets
vacios o incoherentes y releases web. Tras seleccionar se descarga unicamente ese
APK final. Android vuelve a comprobar archivo no vacio, tamano, SHA-256, paquete,
version, build y firma antes de abrir el instalador; nunca admite igual build,
downgrade ni reinstalacion.

`minimumSupportedVersion` solo bloquea el uso cuando la propia release declara
`mandatory: true`; aun entonces el destino es siempre la ultima version valida,
sin instalaciones intermedias. Las publicaciones siguen usando `mandatory:
false` salvo solicitud explicita. Si GitHub no responde, la interfaz ofrece
reintento y solo muestra el ultimo manifiesto que ya fue validado y guardado en
cache. Al iniciar una descarga se eliminan parciales y APK anteriores para
conservar exclusivamente el APK final verificado.

## Emergencias

El workflow **Publicar actualizacion Android** conserva `workflow_dispatch`.
Permite elegir el ref ya versionado. `mandatory` queda en `false`; si el
propietario pide expresamente una actualizacion obligatoria, se activa y se
completa `minimum_supported_version`. Titulo y notas tambien se generan desde la
ultima release Android valida.

## Configuracion y secretos

Mantener el environment protegido `android-release` y estos GitHub Secrets:

- `ANDROID_KEYSTORE_BASE64`.
- `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` y `ANDROID_STORE_PASSWORD`.
- `ANDROID_CERT_SHA256`.
- `SUPABASE_URL` y `SUPABASE_ANON_KEY` para las compilaciones.

Nunca subir el keystore, `key.properties` ni contrasenas. El workflow usa un
keystore temporal y lo elimina siempre. Si falta un secret, la firma no es
valida, el certificado no coincide o faltan metadatos/assets, la ejecucion se
detiene antes de publicar.

## Plantilla para futuros prompts

Una solicitud normal debe decir:

```text
Implementa <cambio>. Clasifica el conjunto como patch, minor o major por impacto,
incrementa version y build con tool/release_version.dart, valida, haz commit con
Release-Type: <tipo> y push a origin/main. La actualizacion Android es opcional.
```

Solo cuando el propietario quiera bloquear versiones anteriores debe anadir:

```text
Esta actualizacion debe ser obligatoria. Usa como version minima x.y.z.
```

Para cada entrega se valida el YAML de los workflows, el script de versionado,
`flutter analyze` si cambio Dart y `git diff --check`. No se genera un APK local.
