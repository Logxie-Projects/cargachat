# Arquitectura Netfleet

> Documento técnico de referencia para el marketplace B2B de subasta inversa de fletes de Logxie Connect S.A.S.
> Dominio: [netfleet.app](https://netfleet.app) · Repo: `Logxie-Projects/cargachat` (branch `main`)

---

## Stack tecnológico

| Capa | Tecnología | Notas |
|------|------------|-------|
| Frontend | HTML5 + CSS + JS vanilla | Sin framework, sin bundler. Cada `.html` es self-contained |
| Mapas | Leaflet 1.9.4 + CartoDB dark tiles | `fitBounds` siempre con `maxZoom:12` (sin esto los tiles quedan grises) |
| Rutas reales | OSRM público (gratis, sin API key) | Fallback a línea recta tras 5s de timeout |
| Geocoding | Diccionario local `CIUDADES` (~200) + Google Geocoding API | El diccionario resuelve el 95%+ de casos |
| Auth + DB | Supabase (`pzouapqnvllaaqnmnlbs.supabase.co`) | Raw fetch con JWT anon key (iat:1775536019). **NUNCA** usar `sb_publishable_` |
| Ingesta de viajes | Gmail → n8n → Google Sheets (CSV público) | Un solo Sheet central, se lee vía `cargarViajes()` |
| Motor de precios | Modelo Ridge polinomial grado 2 (R²=0.919) | Entrenado con 1.015 viajes reales. Mismo algoritmo en frontend y en el nodo de n8n |
| Hosting | Cloudflare Pages (`cargachat.pages.dev` → `netfleet.app`) | Auto-deploy en ~1-2 min al hacer push a `main` |
| Cache | Header `Cache-Control: no-cache` vía `_headers` | Evita servir HTML viejo tras deploy |

---

## Estructura del repo

```
/
├── index.html              → Landing del generador (hero + calculadora + mapa + viajes + subastas)
├── empresa.html            → Portal registro/login para empresas generadoras
├── transportador.html      → Dashboard del transportador (viajes + ofertas + docs)
├── admin.html              → Panel admin Logxie (usuarios + subastas)
├── mis-ofertas.html        → Vista de ofertas del transportador
├── viaje.html              → Tarjeta individual de viaje (screenshots LinkedIn)
├── checkderuta.html        → Check-in de ruta con webhook a n8n
├── analizador-rutas.html   → Análisis de rutas multi-parada
├── netfleet-core.js        → Utilidades compartidas (estimador, geocoding, hash de viaje)
├── supabase.min.js         → SDK Supabase v2.39.8 local (NO cambiar versión)
├── _headers                → Configuración Cloudflare (no-cache)
├── landing_new.html        → Landing alternativa en iteración
│
├── docs/                   → Documentación del proyecto
│   ├── ARQUITECTURA.md        ← este archivo
│   ├── CONTEXTO_OPERATIVO.md  ← estado actual del proyecto
│   ├── CONTEXTO_SESION.md     ← bitácora de sesiones de trabajo
│   ├── PROYECTO_NETFLEET.md   ← ficha del proyecto
│   ├── modelo-precios-n8n.md  ← código del nodo de precio en n8n (v2 actual)
│   └── legacy/
│       └── modelo-precios-n8n-v1.md  ← fórmula lineal antigua (histórico)
│
├── db/                     → Esquemas y migraciones Supabase
│   └── ofertas.sql            ← tabla de subastas
│
├── n8n/                    → Workflows exportados / docs de automatización
│   └── (.gitkeep)
│
└── .gitignore              → excluye xlsx, debug HTML, node_modules, .env
```

### Archivos excluidos del repo (.gitignore)
- `ViajesColombia.xlsx` — dataset de entrenamiento ML, no versionar (binario pesado)
- `ruta_debug.html`, `test_osrm.html` — tools de debug local
- `*.env`, `.env.local`, `node_modules/` — nunca en el repo

---

## Flujo de deploy

```
Edición local (D:\NETFLEET\)
        ↓
   git commit
        ↓
 git push origin main
        ↓
Cloudflare Pages detecta push
        ↓
Build + deploy automático (~1-2 min)
        ↓
  netfleet.app actualizado
```

- **No hay staging ni preview separados.** El push a `main` va a producción.
- **No hay build step** (sin bundler). Cloudflare sirve los archivos tal cual.
- **_headers** en la raíz configura `Cache-Control: no-cache` para forzar recarga del HTML.

---

## Módulos pendientes

### 1. Ingesta multicliente
Hoy el CSV de Google Sheets es una sola tabla compartida entre Avgust y Fateco. El próximo paso es soportar múltiples generadores con segmentación por cuenta: cada empresa genera su propia pestaña o tabla, y el admin ve consolidado. Migración futura a tabla `viajes` en Supabase elimina la dependencia del Sheet.

### 2. Portal transportador (público + auth-gated)
`transportador.html` debe mostrar viajes **sin requerir login**. Solo al hacer clic en "Ofertar →" se dispara el modal de registro/login. Esto aumenta conversión. También falta dashboard de documentos (RUT, tarjeta propiedad, seguros) con estado de vigencia.

### 3. Subasta inversa (cierre + adjudicación)
Tabla `ofertas` ya existe. Pendientes: (a) countdown de cierre por viaje, (b) notificación al adjudicado vía WhatsApp/email, (c) vista comparativa de ofertas para el admin, (d) lock de ofertas tras adjudicación.

### 4. Seguimiento
`checkderuta.html` ya envía check-ins a webhook n8n y persiste en localStorage. Falta: (a) persistencia en Supabase tabla `checkins`, (b) timeline visible para el generador, (c) alertas automáticas por retraso vs ETA de OSRM.

### 5. Analytics
Dashboard agregado para Logxie: viajes por zona, ahorro promedio vs precio base, tasa de adjudicación, tiempo medio de cierre de subasta, transportadoras más activas. Probablemente un `admin-analytics.html` nuevo que consuma vistas materializadas de Supabase.

---

## Decisiones técnicas tomadas

1. **HTML/CSS/JS vanilla, sin framework.** El proyecto es chico, el equipo es uno, y el deploy debe ser instantáneo. Introducir React/Vue añadiría complejidad de build sin beneficio proporcional.

2. **Supabase vía raw fetch, no cliente sb.** Control total sobre headers y errores. El cliente oficial de Supabase añade peso innecesario y oculta detalles que necesitamos ver.

3. **Google Sheets como source de viajes (temporal).** Permite al equipo de ops editar manualmente si n8n falla. Se migrará a tabla `viajes` en Supabase cuando el volumen lo justifique.

4. **Modelo de precios replicado en frontend y n8n.** Debe dar el mismo resultado en ambos lados (estimador del usuario vs precio publicado). Cualquier cambio se hace en paralelo en ambos. Ver `docs/modelo-precios-n8n.md`.

5. **Hash de viaje client-side.** Como el CSV no tiene ID estable, se genera `'v-' + Math.abs(hash).toString(36)` a partir de `origen+destino+fecha+peso`. Mismo algoritmo en frontend y admin.

6. **Landing 100% para el generador.** La bifurcación "¿Empresa o Transportador?" fue eliminada. El transportador tiene su URL propia (`transportador.html`) con link discreto en el nav.

7. **OSRM público en vez de Mapbox/Google Directions.** Gratis, sin API key, sin rate limits agresivos. Aceptable para volumen actual.

8. **`estado: 'aprobado'` (no `'activo'`) en perfiles.** Todo el frontend chequea `estado === 'aprobado'`. No mezclar nomenclatura.

---

## Convenciones del proyecto

### Commits
- Prefijos tipo: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- Mensaje en español, primera línea corta (<70 caracteres)
- Ejemplo: `fix: actualizar CSV_URL al nuevo gid del sheet (1690776181)`

### Nombres de archivo
- Páginas HTML: kebab-case (`mis-ofertas.html`, `check-de-ruta.html`)
- Docs: MAYÚSCULAS para los estratégicos (`ARQUITECTURA.md`), kebab-case para técnicos (`modelo-precios-n8n.md`)
- SQL: nombre de tabla singular o plural consistente con la DB (`ofertas.sql`)

### Código
- Funciones globales con nombre corto y expresivo (`estimarPrecio`, `cargarViajes`, `getCoordenadas`)
- Sin abstracciones prematuras: si algo se usa en 1-2 lugares, es inline
- Comentarios solo cuando el *por qué* no es obvio (un fix de bug, una restricción del runtime)

### Supabase
- Tablas en minúsculas singular o plural según convenio (`perfiles`, `ofertas`)
- Todos los estados como `text` con `check constraint`, no enums de Postgres (más fácil de evolucionar)
- RLS siempre activado. Políticas explícitas por operación (SELECT, INSERT, UPDATE separadas)
- `unique index ... where (estado = 'activa')` para evitar duplicados que respeten estado

### Frontend
- `window.open()` debe llamarse sincrónicamente en el gesture del usuario — nunca después de `await`
- iOS Safari: aplicar `overflow-x:hidden` tanto en `body` como en `html`
- Pins duplicados en mapa: offset de `n * 0.06°` lat para viajes del mismo origen
- `tipo_mercancia`: siempre `(v.tipo_mercancia || '').trim() || 'General'`

---

*Última actualización: 2026-04-17*
