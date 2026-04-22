# NETFLEET + LOGXIA — Fuente de Verdad
> Logxie Connect S.A.S. · Bernardo Aristizabal · bernardoaristizabal@logxie.com · +573214401975

---

## Cómo arrancar una sesión nueva

- **Claude Code:** este archivo se carga automáticamente al abrir el repo en `D:\NETFLEET`
- **Claude chat:** adjuntar este archivo o escribir "lee CLAUDE.md y continuemos"
- **Primer pase obligatorio:** después de este archivo, leer `docs/CONTEXTO_OPERATIVO.md` para el estado vivo del día (qué está en producción, qué está a medias, próximos pasos). Complementa — no reemplaza — CLAUDE.md.
- **Al terminar cada sesión:**
  - Actualizar sección Pendientes: marcar ítems completados con `✅ hecho YYYY-MM-DD` (no borrarlos, son trazabilidad)
  - Actualizar `docs/CONTEXTO_OPERATIVO.md` si cambió el estado operativo
  - Si se tomó una decisión estructural, agregarla a "Decisiones Técnicas Tomadas"

### Fuentes de verdad — qué vive dónde

| Archivo | Contenido | Cambia |
|---|---|---|
| `CLAUDE.md` (este) | Reglas, decisiones duras, accesos, arquitectura estable, funciones protegidas | Raramente |
| `docs/CONTEXTO_OPERATIVO.md` | Estado operativo vivo (qué está en prod, pendientes por prioridad) | Cada sesión |
| `docs/ARQUITECTURA.md` | Profundización técnica del stack, módulos pendientes, convenciones | Cuando cambia la arquitectura |
| `docs/LOGXIA_JOURNEY.md` | **Journey operativo + spec de reglas autopilot por fase (🟢🟡🔴)**. Tabla 7 pasos × [hoy · Fase 1 · Fase 2 · Fase 3], reglas priorizadas, sistema de rating, Módulo 6 Facturación | Cuando se activa una regla o cambia prioridad |
| `docs/CONTEXTO_SESION.md` | Bitácora histórica de sesiones (append-only) | Al cierre de cada sesión |

Si dos fuentes divergen, **CLAUDE.md gana para reglas y decisiones**, `CONTEXTO_OPERATIVO.md` gana para estado actual, `docs/LOGXIA_JOURNEY.md` gana para "qué regla autopilot viene después y por qué".

---

## El negocio — Logxie Connect S.A.S.

BPO logístico 4PL/5PL con sede en Guadalajara de Buga, Valle del Cauca. Fundador: Bernardo Aristizabal — Ing. Electrónico (Javeriana Cali), Supply Chain (MITx), IA sin código (MIT), Estrategia (IE Business School). 22 años en SLB liderando logística global en África, América y Latam. Nivel Growth YSA Región Pacífico.

Logxie ofrece dos cosas: **BPO logístico** (operación) y **tecnología propia** (Netfleet + LogxIA).

**Métricas:** 2.000+ viajes · 9.9M kg · 98% entregas a tiempo
**Cliente activo:** Avgust (multinacional) y filial Fateco · proyectos@avgust.com.co

---

## Arquitectura del negocio

```
LOGXIE CONNECT S.A.S.
├── NETFLEET — Plataforma tecnológica (marketplace + apps operativas)
│   ├── netfleet.app              → Landing generadores de carga
│   ├── /transportador.html       → Portal transportadores
│   ├── /analizador-rutas.html    → Planificación de entregas
│   └── Apps internas             → Migración desde AppSheet
└── LOGXIA — Agente IA operativo
    ├── Seguimiento a transportadores (activo)
    ├── Bot Telegram conversacional (activo)
    └── Consolidación inteligente (futuro)
```

---

## Accesos y Credenciales

| Recurso | Valor |
|---|---|
| Carpeta local | `D:\NETFLEET` |
| GitHub repo | `https://github.com/Logxie-Projects/cargachat` (branch `main`) |
| Sitio en vivo | `https://netfleet.app` |
| Cloudflare Pages | `cargachat.pages.dev` (auto-deploy en push a `main`) |
| Supabase URL | `https://pzouapqnvllaaqnmnlbs.supabase.co` |
| Admin panel | `https://netfleet.app/admin.html` |
| n8n | `https://n8n.srv1173119.hstgr.cloud` |
| Google Maps API Key | `AIzaSyBSDer_Cdp3pNhZrebp6h5OWDfHQkWJifo` |
| Screenshotone Access Key | `GXbCQqwCqsYR6A` |

### DATABASE_URL para scripts SQL (db/run_migration.py, db/sync_from_csv.py)

**Pooler** (recomendada — funciona en bash y PowerShell, URL-encoded):
```
postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres
```

**Direct** (backup — sin URL-encoding, PowerShell la tolera):
```
postgresql://postgres:Bjar1978*ABC@db.pzouapqnvllaaqnmnlbs.supabase.co:5432/postgres
```

**Para no pegarla en cada sesión nueva**, corre UNA vez en PowerShell:
```powershell
[System.Environment]::SetEnvironmentVariable('DATABASE_URL',
  'postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres',
  'User')
```
Cerrá y reabrí la terminal — queda persistente en Windows.

**Uso típico** (Git Bash desde Claude Code):
```bash
export DATABASE_URL="postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
export PYTHONIOENCODING=utf-8
PYTHON="$LOCALAPPDATA/Programs/Python/Python313/python.exe"
"$PYTHON" db/run_migration.py --file db/<archivo>.sql
```

**Deploy:** `git add archivo && git commit -m "descripción" && git push origin main`
Cloudflare despliega automáticamente en ~1-2 minutos.

---

## Estructura del Repo

```
D:\NETFLEET\
├── index.html                  → Landing generador (HTML+CSS+JS todo en uno)
├── transportador.html          → Portal transportadores (login + viajes + ofertas)
├── empresa.html                → Portal registro/login empresas generadoras
├── admin.html                  → Panel admin Logxie
├── control.html                → Panel de control staff Logxie (Módulo 4 UI: consolidar/subasta/activos/scenarios/historial/catálogo)
├── mis-ofertas.html            → Vista ofertas del transportador
├── viaje.html                  → Tarjeta individual (screenshots LinkedIn)
├── checkderuta.html            → Módulo seguimiento de ruta en tiempo real
├── analizador-rutas.html       → Planificador multi-parada: lee Supabase (viajes_consolidados + scenarios_viaje), selector dual 🚚 Viaje / 🧪 Scenario, deep-link ?scenario= / ?viaje=, OSRM + Leaflet + ETAs + PDF. Fallback CSV con ?legacy=1
├── q.html                      → Quote (propuesta) standalone para compartir
├── netfleet-core.js            → Funciones compartidas (inactivo — no lo carga ningún HTML todavía)
├── supabase.min.js             → SDK Supabase v2.39.8 (NO cambiar versión)
├── _headers                    → Cache-Control: no-cache para Cloudflare
├── .gitignore                  → Excluye secretos (LogxIA/CLAVES Y APIS.txt), xlsx, .claude/settings.local.json
├── CLAUDE.md                   → Este archivo
├── README.md                   → Inventario LogxIA (a nivel raíz)
├── /docs/                      → Documentación técnica
│   ├── ARQUITECTURA.md         → Stack, estructura, módulos pendientes, decisiones, convenciones
│   ├── CONTEXTO_OPERATIVO.md   → Estado actual: producción, pendientes, próximos pasos
│   ├── CONTEXTO_SESION.md      → Bitácora de sesiones
│   ├── PROYECTO_NETFLEET.md    → Ficha del proyecto
│   ├── modelo-precios-n8n.md   → Código Ridge v2 del nodo de precio en n8n
│   └── /legacy/
│       └── modelo-precios-n8n-v1.md  → Fórmula lineal antigua (histórico)
├── /dumps/                     → CSV exports de Google Sheets (gitignored, para backfill local)
├── /db/                        → Schemas SQL + funciones + migrations Supabase
│   ├── perfiles.sql            → Schema perfiles + is_logxie_staff() + trigger handle_new_user
│   ├── clientes.sql / viajes.sql / pedidos.sql → schemas base M2
│   ├── ofertas.sql / modulo4_schema*.sql / modulo4_functions.sql → Módulo 4
│   ├── modulo4_reabrir.sql     → fn_reabrir_viaje (revierte confirmado → pendiente)
│   ├── modulo4_sync.sql        → fn_sync_viajes_batch + fn_sync_pedidos_batch
│   ├── modulo4_norm_empresa.sql → _norm_empresa() helper (canonicaliza "FATECO, AVGUST")
│   ├── modulo4_revision_pedidos.sql → fn_marcar_revisado/no_revisado (Fase 1 pipeline)
│   ├── modulo4_cerrar_viaje.sql → fn_cerrar_viaje + fn_cerrar_viajes_batch
│   ├── modulo4_reabrir_finalizado.sql → fn_reabrir_finalizado (deshace cierre)
│   ├── modulo4_pedidos_bulk.sql → fn_pedidos_cancelar/resetear_batch + fn_pedido_clonar
│   ├── modulo4_pedidos_admin.sql → fn_pedido_editar + cambiar_estado_batch + eliminar_batch
│   ├── scenarios_viaje.sql     → Capa tentativa: 2 tablas + 6 fns (crear/agregar/quitar/descartar/limpiar/promover)
│   ├── scenarios_viaje_patch_constraint.sql → Patch extender CHECK acciones_operador con scenario_*
│   ├── link_pedidos_viajes_v3.sql → linker v3 regex (aliases no rangos) — pase 1
│   ├── link_pedidos_viajes_v4.sql → linker v4 substring BUSCARX-style — pase 2 (97.3% combinado)
│   ├── smoke_test_modulo4.sql  → E2E test del ciclo completo M4
│   ├── sync_from_csv.py        → Python CLI para backfill + ETL manual desde CSV
│   ├── run_migration.py        → Script ejecutor de .sql contra Supabase
│   └── migrate_*.sql           → Dumps históricos (gitignored, obsoletos post-sync)
└── /LogxIA/                    → Agente IA LogxIA — workflows n8n + docs
    ├── LogxIA — Parser Detalle Pedidos.json
    ├── LogxIA_Bot_Telegram.json
    ├── AvgustIA_Lector_de_Pedidos.json
    ├── AvgustIA_Seguimiento_Transportadores.json
    ├── CLAVES Y APIS.txt       → ⚠️ GITIGNORED — no versionar
    └── /docs/
        └── checkderuta.md
```

**Archivos eliminados (sesión 2026-04-17):** `landing.html`, `landing_new.html`, `index_backup_20260413.html`, `transportador_backup_20260413.html`. El landing definitivo es `index.html`.

---

## Stack Técnico NETFLEET

- **Frontend:** HTML/CSS/JS puro — sin framework, sin bundler
- **Mapas:** Leaflet.js v1.9.4 + CartoDB dark tiles + OSRM (rutas reales)
- **Auth & DB:** Supabase — siempre raw fetch con headers explícitos, NUNCA el cliente sb para PostgREST
- **Datos viajes:** Google Sheets → CSV público → `CSV_URL` en index.html línea 1186
- **Geocoding:** Diccionario local `CIUDADES` (~200 ciudades) + Google Geocoding API fallback
- **Precios:** Modelo Ridge R²=0.919 entrenado con 1.015 viajes reales
- **Automatización:** n8n self-hosted en Hostinger VPS
- **Deploy:** Cloudflare Pages desde GitHub
- **Analytics:** Cloudflare Insights (`beacon.min.js` — NO tocar)

**CRÍTICO — Supabase:** Usar siempre el JWT anon key largo (`iat:1775536019`). NUNCA el `sb_publishable_` key.

---

## Ecosistema AppSheet — Apps activas (a migrar a Netfleet)

| App | Usuarios | Función | Reemplazada por |
|---|---|---|---|
| AVGUST Transport Request | Equipo Logxie/Avgust | Crear solicitudes → `Base_inicio-def` | Módulo 2: Ingesta multicliente |
| Control Transporte | Bernardo | Consolida pedidos → genera mail SOLICITUD → dispara n8n | Módulo 4: Control y consolidación |
| Donde Está mi Pedido | Transportadoras | Subir cumplidos, fotos, horarios | Módulo 3: Seguimiento y cumplidos |
| Navegador | Conductores | Actualizar info en tiempo real | Módulo 3: Seguimiento y cumplidos |

---

## Flujo Operativo Avgust (hoy)

```
Vendedor visita cliente → CRM Avgust
    → equipo Logxie crea solicitud en AppSheet Transport Request
    → Base_inicio-def (Google Sheet)
    → Bernardo consolida en APP Control Transporte
    → Mail "SOLICITUD DE SERVICIOS" (1 mail = 1 viaje consolidado)
         ↓                                      ↓
  n8n LinkedIn+Viajes                  n8n Parser Detalle
  → VIAJES_PUBLICOS (Sheet)            → DETALLE_PEDIDOS (Sheet)
  → netfleet.app (mapa)                → analizador-rutas.html
  → LinkedIn post (desactivado)
```

**Importante:** el mail es la unidad de análisis — refleja la decisión de consolidación. No se analiza `Base_inicio-def` directamente porque los pedidos se despachan agrupados según lo que Bernardo decide consolidar.

**Flujo futuro:** CRM Avgust → directo a Sheet sin intervención manual. LogxIA decide consolidación automáticamente.

---

## Arquitectura Google Sheets

**Sheet principal — Transportes Avgust Colombia**
ID: `1rqCdVATX9cWQJ3zL2s5PO82EE_KmXTqIeg_oj7DAHE4`

| Pestaña | Cómo se llena | Propósito |
|---|---|---|
| Base_inicio-def | AppSheet Transport Request | Entrada de todas las solicitudes |
| Pedidos_Consolidados | Copia temporal | Pedidos sin transporte asignado |
| ASIGNADOS | Script desde Control Transporte | Suma pesos/valores, envía mail a proveedores |
| DATA UNIFICADA | Fórmula espejo Base_inicio-def | Analytics + Looker Studio |
| VIAJES_PUBLICOS | n8n LinkedIn+Viajes | Viajes disponibles. Columnas A-U con km, precio, zona |
| VIAJES_LANDING | QUERY sobre VIAJES_PUBLICOS | CSV público → netfleet.app |
| DETALLE_PEDIDOS | n8n Parser Detalle | 1 fila por pedido individual → analizador-rutas.html |

**Sheet secundaria — Seguimiento y Cumplidos**
Alimentada por IMPORTRANGE desde DATA UNIFICADA. Consumida por APP Donde Está mi Pedido y Navegador. Se elimina con Módulo 3.

**CSV VIAJES_LANDING:** `gid=1690776181` · `CSV_URL` en `index.html` línea 1186
**CSV DETALLE_PEDIDOS:** `gid=749562420` · consumido por `analizador-rutas.html`

**Síntoma de rotura:** mapa muestra solo 2 viajes hardcoded. Fix: Archivo → Publicar en la Web → republicar → actualizar URL → push.

---

## Workflows n8n — Inventario Definitivo

### ACTIVOS EN PRODUCCIÓN

**1. LinkedIn + Viajes**
- **Trigger:** Gmail cada minuto — subject `SOLICITUD DE SERVICIOS`
- **Flujo:** Gmail → If → Code JS2 (parsea resumen HTML/texto) → Distance Matrix → Code JS3 (precio Ridge + zona) → 3 ramas paralelas:
  - Google Sheets → VIAJES_PUBLICOS → netfleet.app ✅ ACTIVO
  - AI Agent Gemini → post LinkedIn ⏸ DISABLED
  - Screenshotone → imagen viaje.html ⏸ DISABLED
- **⚠️ Pendiente:** URL Screenshotone apunta a `cargachat.netlify.app` — cambiar a `netfleet.app` al reactivar LinkedIn
- **Parser maneja:** mail original AppSheet (HTML limpio) y Fwd (asteriscos)

**2. AvgustIA — Seguimiento a Transportadores**
- **Trigger:** Schedule 6am / 12pm / 6pm
- **Flujo:** Ejecuta Lector → filtra estado vacío o `Pendiente` → agrupa por proveedor → mail HTML a cada transportador
- **Transportadores configurados:** PRACARGO, ENTRAPETROL, TRASAMER, JR LOGÍSTICA, TRANS NUEVA COLOMBIA
- **CC siempre:** bernardojaristizabal@gmail.com, proyectos@avgust.com.co

**3. LogxIA — Bot Telegram Conversacional**
- **Trigger:** Telegram webhook
- **Flujo:** Valida usuario → Ejecuta Lector → Resuelve consulta → Si necesita Claude API → llama Claude → Si urgente → envía mail → Responde Telegram
- **Capacidades actuales:** consultas de estado, alertas urgentes, notificación a proveedores

**4. AvgustIA — Lector de Pedidos** *(subworkflow — no necesita estar activo)*
- **Fuente:** Google Sheet "Seguimiento y Cumplidos" → pestaña "Datos desde Unificada"
- **Output:** totalPedidos, pedidosSinEstado, pedidosPendientes, pedidosConNovedad, pedidosEntregadosOK, listaPedidos
- **Estados válidos:** `Pendiente` · `Entregado OK` · `Entregado con Novedad` · `Rechazado por Cliente` · vacío = sin reporte

**5. LogxIA — Parser Detalle Pedidos**
- **Nombre en n8n:** `LogxIA — PRODUCCIÓN v2 (Mails Avgust)` *(pendiente renombrar)*
- **Trigger:** Gmail — `proyectos@avgust.com.co` subject `SOLICITUD DE SERVICIOS`
- **Flujo:** Gmail Trigger → HTTP (leer body completo base64) → Parser JS → DETALLE_PEDIDOS (Sheet)
- **Output por pedido:** VIAJE_ID, REMISION, EMPRESA, ZONA, ORIGEN, DESTINO, PESO_KG, VALOR_MERCANCIA, DIAS_ATENCION, V1_DESDE/HASTA, V2_DESDE/HASTA, HORARIO_SABADO, CLIENTE, CONTACTO, TELEFONO, DIRECCION, NOTAS, LLAMAR_ANTES
- **Fix clave:** `.replace(/\*/g, '')` maneja mails reenviados con asteriscos
- **Credenciales:** Gmail `wwd5v7WrftObobuR`, Sheets `IuCNLIa09oW4ZWBu`
- **Consumidor:** `analizador-rutas.html`

---

## Base de Datos Supabase

### Tabla `perfiles`
```
id, email, nombre, empresa, telefono, nit
tipo: 'transportador' | 'empresa'
estado: 'pendiente' | 'aprobado' | 'rechazado'
```
Trigger `handle_new_user()` crea la fila al registrarse.
**CRÍTICO:** código chequea `estado === 'aprobado'`. NO usar `'activo'`.

### Tabla `ofertas`
```
id, viaje_rt, usuario_id, nombre, empresa, telefono
precio_oferta, comentario
estado: 'activa' | 'aceptada' | 'rechazada' | 'cancelada'
```
`viaje_rt` = `'v-' + Math.abs(hash).toString(36)` — mismo algoritmo en frontend y admin.

### Tabla `leads`
```
id, nombre, empresa, whatsapp, email, sector, fuente, created_at
```

### Tabla `cargas`
```
id, lead_id (FK), origen, destino, peso_kg, tipo_carga, num_paradas
valor_mercancia, precio_estimado, zona, estado, notas, created_at
```

### Tabla `viajes_consolidados` (Módulo 2 — creada 2026-04-17)
Unidad de transporte asignada a un proveedor. Migra desde Sheet ASIGNADOS.
Esquema completo en [db/viajes.sql](db/viajes.sql) — 35 columnas, RLS activado.
1.281 registros históricos migrados. Ver sección **Módulo 2** abajo.

### Tabla `pedidos` (Módulo 2 — creada 2026-04-17)
Pedido individual hacia un cliente final. Migra desde Sheet Base_inicio-def.
FK hacia `viajes_consolidados` (nullable hasta consolidación) y `clientes` (NOT NULL).
Esquema en [db/pedidos.sql](db/pedidos.sql). 3.764 registros migrados.

### Tabla `clientes` (Módulo 2 — creada 2026-04-17)
Configuración por cliente generador de carga + canal de ingesta.
Esquema en [db/clientes.sql](db/clientes.sql). Pobladas: AVGUST, FATECO.

### Tablas `scenarios_viaje` + `scenarios_viaje_pedidos` (Módulo 4 — creadas 2026-04-22)
Capa tentativa de consolidación. Un **scenario** agrupa pedidos sin comprometerlos — el pedido sigue en `sin_consolidar` mientras esté en N scenarios borrador. Solo al **promover** un scenario se crea el viaje real vía `fn_consolidar_pedidos`.

- `scenarios_viaje` (22 cols): nombre, estado (`borrador|promovido|descartado|conflictivo|invalidado`), agregados (peso/valor/zonas), `promovido_a_viaje_id`, notas, audit.
- `scenarios_viaje_pedidos` (N:M): scenario_id + pedido_id + orden.
- 6 Postgres functions: `fn_scenario_crear`, `fn_scenario_agregar_pedido`, `fn_scenario_quitar_pedido`, `fn_scenario_descartar`, `fn_scenario_limpiar_consumidos`, `fn_scenario_promover` (delega a `fn_consolidar_pedidos` y marca otros scenarios como `conflictivo` o `invalidado` automáticamente).
- RLS staff-only. Esquema completo en [db/scenarios_viaje.sql](db/scenarios_viaje.sql).

**State machine scenarios:**
```
borrador → promovido (viaje_X) | descartado | conflictivo → borrador (tras limpiar)
                                                         → invalidado
```

**Regla clave:** el estado del pedido NO cambia por estar en scenarios — solo cambia al promover un scenario o al consolidar directo.

Ver contexto completo en [docs/LOGXIA_JOURNEY.md](docs/LOGXIA_JOURNEY.md).

---

## Algoritmo de Precio — PROTEGIDO

Las funciones `cc*` son el algoritmo propietario. **NO modificar sin instrucción explícita.**

```javascript
function estimarPrecio(km, kg, paradas, destino, origen) {
  if (km < 50) {
    return Math.max(300000, 260000 + kg*28 + 63186*(paradas-1));
  } else {
    return Math.max(950000,
      3097.69*km + 217.94*kg + 0.1215*km*kg
      - 1.0566*km*km - 0.0034*kg*kg
      + 63186*paradas + ajusteZona - 306248
    );
  }
}
```

Ajustes de zona (COP aditivos): ANTIOQUIA +15.7K · BOYACÁ +87.7K · CUNDINAMARCA +65.6K · LLANOS +159.2K · NORTE +79.2K · OCCIDENTE +10.7K · ORIENTE -176.4K · SANTANDERES -213.5K · SUR +79.2K · VALLE +34.2K · EJE CAFETERO -18.8K · TOLIMA/HUILA -18.1K · HUB 0.

Precios fijos Buenaventura: ↔ Yumbo $3M · ↔ Espinal $6M · ↔ Funza $7M.
Mínimo absoluto: $950.000. Techo: 2.8% valor mercancía.

Mismo algoritmo en n8n nodo Code JS3 del workflow LinkedIn+Viajes.

---

## Equipo Avgust / Fateco

| Nombre | Usuario | Rol |
|---|---|---|
| María Paula Contreras | p.contreras | Operativa / Reclamos |
| Ramiro Barrios | r.barrios | Operaciones |
| William Barrero | w.barrero | Operaciones |
| Julián Capera | j.capera | Coordinación |
| Jhonatan Yaguara | j.yaguara | Fateco / Soportes transporte |
| Angélica Carrillo | a.carrillo | Siniestros / Legal |
| María Camila Vahos | c.vahos | Facturación |

**Aprobadores pedidos urgentes / % flete elevado:**
Don Miguel y Don Carlos (aprobadores principales) · Marina (CC siempre) · Bernardo (CC siempre)

**Transportadores activos:**
Entrapetrol (Jeimmy Socha) · Trans Nueva Colombia (Cristhian Gomez) · JR Logística · Global Logística · Vigía · Trasamer (Jahir Muñoz)

---

## Decisiones Técnicas Tomadas

- **Landing bifurcada:** `index.html` solo para generador. Transportador tiene su propia URL. Nav tiene link discreto "¿Eres transportador?"
- **Google Sheets como fuente transitoria:** las tablas `viajes_consolidados` y `pedidos` ya existen en Supabase (Módulo 2, migradas 2026-04-17), pero el Sheet sigue siendo la fuente de ingesta hasta que los 4 parsers n8n estén construidos
- **Mail como unidad de consolidación:** el parser lee el mail (no el Sheet base) porque el mail ya refleja la decisión de agrupamiento operativo
- **n8n self-hosted:** punto de fragilidad conocido — si cae el VPS, se detienen todos los workflows
- **Repo nombre:** `cargachat` en GitHub — renombrar a `netfleet` requiere reapuntar Cloudflare Pages primero
- **Deuda técnica — 5 copias de CIUDADES/estimarPrecio:** `index.html`, `transportador.html`, `analizador-rutas.html`, `viaje.html` y `netfleet-core.js` tienen cada uno su propio diccionario + funciones. Cualquier cambio debe replicarse en los 5. Centralizar está pendiente (Paso 2).
- **Ciudades ambiguas hardcodeadas:** Santa Rosa → de Cabal (Risaralda), Miraflores → Boyacá. Heurístico de centroide para elegir la variante correcta queda para cuando se centralice.

---

## Funciones JavaScript — NO TOCAR SIN INSTRUCCIÓN EXPLÍCITA

**Pricing (PROTEGIDO):** `estimarPrecio()` · `ccCalc()` · `ccDetectarZona()` · `ccNorm()` · `ccFmt()` · `ccRango()`

**Ruteo (PROTEGIDO):** `obtenerRutaOSRM()` · `getCoordenadas()` · `getCoords()` · `geocodeCiudad()` · `crearMarkerOrigen()` · `initMapa()` · `variantes()` · `normalizarNombre()`

**Roles y UI:** `setRol()` · `aplicarRol()` · `actualizarSeccionesRol()` · `actualizarTickerRol()` · `actualizarNav()` · `toggleFab()`

**Auth:** `iniciarSesion()` · `registrarse()` · `cerrarSesion()` · `fetchPerfil()` · `cambiarAuthTab()`

**Modales:** `abrirSelectorModal()` · `abrirAuthModal()` · `abrirVinculacionModal()` · `abrirLeadModal()` · `abrirOfertaModal()` · `cerrarModalOverlay()`

**Viajes:** `cargarViajes()` · `renderViajes()` · `seleccionarViaje()` · `buscarViajes()` · `revisarNuevosViajes()` · `cargarConteosOfertas()`

---

## Dev local

Hay un servidor estático PowerShell en `.claude/serve.ps1` configurado en `.claude/launch.json` bajo el nombre `static-server` (puerto 8080).

**Desde Claude Code:** arrancar con `preview_start` → `static-server`. Abrir `http://localhost:8080/<pagina>.html`. Verificar cambios en browser con `preview_eval`, `preview_console_logs`, `preview_screenshot`, etc.

**Desde terminal manual:** `powershell -ExecutionPolicy Bypass -File .claude/serve.ps1`

La ruta `/` redirige a `transportador.html` por default. El servidor sirve cualquier archivo del repo tal cual (sin build step).

**Uso típico:** cualquier cambio a HTML/JS que afecta el mapa, geocoding, UI o `cargarViajes()` debe verificarse en browser antes de pushear a `main` (Cloudflare despliega directo a prod).

---

## Notas Técnicas Importantes

- `window.open()` debe llamarse sincrónicamente en el gesture del usuario — nunca después de `await`
- `fitBounds` siempre con `maxZoom:12` — sin esto los tiles Leaflet quedan grises
- iOS Safari: `overflow-x:hidden` en `body` rompe `position:fixed` — aplicarlo también al elemento `html`
- FAB flotante: `right:6px` por defecto, `right:24px` en `@media(min-width:769px)`
- Pins duplicados en el mapa: offset de `n * 0.06°` lat para viajes del mismo origen
- `tipo_mercancia`: `(v.tipo_mercancia || '').trim() || 'General'`
- Parser n8n: usar `$json.html` primero → fallback `$json.text` con `.replace(/\*/g, '')`
- `getCoordenadas()` hace 2 pasadas: exact match primero, substring solo para candidatos ≥5 chars. Evita que "santa" (variante corta de "Santa Rosa") matchee "santa marta" por substring. Cualquier cambio debe replicarse en los 5 archivos (ver deuda técnica arriba).

---

## Roadmap Módulos NETFLEET

| # | Módulo | Reemplaza | Estado |
|---|---|---|---|
| 1 | Subasta inversa | Mail + Google Forms | Base funcional — landing, transportador.html, tabla ofertas |
| 2 | Ingesta multicliente | AppSheet Transport Request | Schema ✅ + Sync ✅ + Linker v3+v4 cascada (97.3% link) ✅ 2026-04-20. Falta botón 🔄 Sync + cron 15min |
| 3 | Seguimiento y cumplidos | Donde Está mi Pedido + Navegador | Pendiente |
| 4 | Control y consolidación | Control Transporte + script Sheets | Backend + UI + sync + admin pedidos + Kanban Fase 1 ✅ 2026-04-20. Pendiente: botón Sync, email notificaciones, deep-linking, Kanban Fase 2 |
| 5 | Analytics | DATA UNIFICADA + Looker Studio | Pendiente |

---

## Pendientes Prioritarios

> **Convención:** al completar un ítem, **no borrarlo** — marcarlo con `✅ hecho YYYY-MM-DD` al inicio. Mantiene trazabilidad y permite que sesiones futuras vean qué se cerró cuándo. Solo se borra cuando el ítem pierde relevancia (ej: decisión de producto que cambió).

### 🔥 Seguridad
- [ ] **Rotar Anthropic API key** en [console.anthropic.com](https://console.anthropic.com/settings/keys) — quedó en texto plano en `LogxIA/CLAVES Y APIS.txt` antes de gitignorarla. Asumir comprometida.
- [ ] **Rotar Telegram bot token** en `@BotFather` → `/revoke` → `/token`

### Refactor — Paso 2
- [ ] **Unificar las 5 copias de CIUDADES/estimarPrecio** en `netfleet-core.js` + `<script src="netfleet-core.js">` en cada HTML. Borrar copias locales.

### Producto
- [x] ✅ hecho 2026-04-22 — **Capa Scenarios (Módulo 4)** — un pedido puede estar en N scenarios tentativos mientras siga sin_consolidar. Schema `scenarios_viaje` + `scenarios_viaje_pedidos`, 6 Postgres functions (`fn_scenario_crear/agregar_pedido/quitar_pedido/descartar/limpiar_consumidos/promover`), RLS staff-only. Sub-tab 🧪 Scenarios en control.html + modal dual (scenario/directo/promover), badge 🧪 N en fila de pedido. Ver [db/scenarios_viaje.sql](db/scenarios_viaje.sql), [docs/LOGXIA_JOURNEY.md](docs/LOGXIA_JOURNEY.md).
- [x] ✅ hecho 2026-04-22 — **Analizador-rutas migrado a Supabase** — lee `viajes_consolidados` + `scenarios_viaje` en vez del CSV. Selector dual 🚚 Viaje / 🧪 Scenario, deep-link `?scenario=<id>` / `?viaje=<id>`, parser simple del campo `horario` texto → v1/v2. Fallback CSV legacy con `?legacy=1`. Botón "🗺 Analizar ruta" desde cards de scenario en control.html.
- [x] ✅ hecho 2026-04-22 — **Badge zona inline + sub-split por zona en modo "Agrupar por Origen"** — 13 colores canónicos (BOYACÁ, VALLE, etc.) junto al destino. Dentro de un grupo de origen, separa automáticamente los consolidables (ej. Funza→Boyacá) de los no-consolidables (ej. Funza→Pasto). Elimina filtrado mental del operador.
- [ ] **Regla #1 Fase 1 — Auto-swap destino↔dirección** (80 h/año estimadas). Requiere centralizar catálogo CIUDADES en netfleet-core.js primero. Ver [docs/LOGXIA_JOURNEY.md](docs/LOGXIA_JOURNEY.md).
- [ ] **Rating implícito Fase 0** — calcular desde datos existentes (% on-time, % entregado_ok, % cumplidos a tiempo). Prerequisito del panel comparativo de ofertas.
- [ ] **Renombrar** `LogxIA — PRODUCCIÓN v2 (Mails Avgust)` → `LogxIA — Parser Detalle Pedidos` en n8n
- [ ] **LogxIA:** agregar Vigía y Global Logística al diccionario `CORREOS_PROVEEDORES` en Seguimiento Transportadores
- [ ] **LogxIA:** poblar `ADMIN_IDS` y arrays de Telegram IDs por proveedor en Bot Telegram
- [ ] **transportador.html:** rediseño — viajes públicos sin login, registro 2 pasos al ofertar
- [ ] **Reactivar LinkedIn** en workflow LinkedIn+Viajes — cambiar URL Screenshotone a `netfleet.app`
- [ ] **Renombrar repo** `cargachat` → `netfleet` en GitHub (reapuntar Cloudflare Pages primero)
- [x] **Tabla `viajes` Supabase:** ✅ hecho 2026-04-17 — renombrada a `viajes_consolidados`, migrada desde Sheet ASIGNADOS (1.281 registros). Parte del Módulo 2.
- [ ] **empresa.html:** formulario publicación de carga → Supabase tablas `viajes_consolidados` + `pedidos`
- [ ] **og-image.png:** 1200×630px para preview WhatsApp/LinkedIn
- [ ] **Módulo 2 — Ingesta Multicliente:** ✅ hecho 2026-04-17 (SQL ejecutado: 2 clientes, 1281 viajes consolidados, 3764 pedidos con cliente_id). Falta: construir los 4 parsers n8n (email, sheet pull, webhook, sheet ASIGNADOS legacy)
- [ ] **LogxIA Módulos 3-5:** Consolidación inteligente, Pricing dinámico, Predicción de demanda
- [x] ✅ hecho 2026-04-22 — **Drive API — links directos a foto/PDF cumplido**. Proyecto Cloud dedicado **NETFLEET** creado con key `AIzaSyBo3eh8YWuP-tdcIYBl_NbWxjqATTa5Tyc` (restringida a Drive API + referrers netfleet.app/* + localhost). Folders compartidas "Anyone with the link". `resolverCumplidosAsync` en control.html consulta cada folder por separado (OR en single query da 403 con API key sin OAuth), cachea filename→fileId, devuelve URL `drive.google.com/file/d/<id>/view`. Badges 📷 Foto / 📄 PDF junto al estado de cada pedido en bloque tracking.
- [ ] **Seguimiento Proactivo (mails de estado)** — Módulo nuevo. Enviar mails automáticos cuando cambia estado del viaje/pedido: adjudicado → coordinador+vendedor; salida_cargue → coord+vendedor+jefe_zona; entregado → todos+cliente; novedad/rechazo → alerta coord+vendedor+jefe_zona; devuelto_bodega → crítica todos. **Bloqueadores**: (1) campos `vendedor` y `jefe_zona` en pedidos son solo nombres, no emails — falta directorio Avgust nombre→email (opción A: tabla supabase `personas_avgust`, opción B: pestaña Sheet con mapping, opción C: Avgust agrega email al Sheet ASIGNADOS). `coordinador` sí trae email directo. (2) Stack propuesto: trigger Postgres insert en `eventos_notificacion` (pendiente, enviado_at NULL) + n8n cron 5min lee, resuelve emails, manda via Gmail (mismo stack AvgustIA), marca enviado. Evita duplicados via UNIQUE(evento_id, destinatario). (3) Templates HTML con branding Logxie o texto plano — decidir.
- [x] ✅ hecho 2026-04-22 — **Deep-linking `?viaje_ref=RT-TOTAL-xxx`** implementado en `mi-netfleet.html` (no transportador.html, que ahora es landing). Scroll + pulse highlight + auto-open modal de oferta si logueado. Espera a que `cargarViajes` y `cargarMisOfertas` terminen via `window.__viajesReady`. Funciona end-to-end probado con cuenta JR.
- [ ] **Modificar mail AppSheet → Netfleet** — el Apps Script que genera "SOLICITUD DE SERVICIOS" hoy incluye link a Google Form. Cambiar a `https://netfleet.app/transportador.html?viaje_ref={{ID_CONSOLIDADO}}`. Queda el mail igual, solo cambia el link. Primer paso concreto para sacar el Form.
- [ ] **Apagar Google Form de bidding** — cuando deep-linking + mail esté en producción y veamos ofertas llegando a `ofertas` vs Form, deprecar el Form. Marcar "ya no uses esto".
- [ ] **Autofill flete_total via Ridge** — similar a `fn_autofill_km_viaje`. Cuando llega null, el primer cliente que lo calcula lo persiste. Ahora solo muestra estimado en UI sin grabar.
- [ ] **`tipo_mercancia_default` en tabla clientes** — hoy hardcoded (AVGUST/FATECO → Químico) en transportador.html cargarViajes. Escalable: agregar columna `clientes.tipo_mercancia_default` y leer. Hacerlo cuando sumes un cliente no-químico.
- [ ] **Auto-cerrar viajes >N días** — viajes con fecha_cargue más de 60 días atrás y estado no terminal → auto-finalizar. Previene acumulación stale. Agregar al sync cron o a un cron separado.
- [ ] **Rediseñar `transportador.html` como landing marketing-first** — 2 CTAs claras en hero: "Soy Transportadora (empresa)" / "Soy Conductor Independiente". Cada CTA abre modal auth con `subtipo_transportador` pre-seteado. Registro diferenciado. Hoy es un clone del panel; hay que slim a marketing + login.

---

## Módulo 2 — Ingesta Multicliente (diseño completo)

### Visión
Plataforma multicliente que recibe pedidos de cualquier fuente y produce un pedido canónico idéntico. El resto del sistema nunca sabe de dónde vino el pedido. Objetivo: escalar Logxie más allá de Avgust.

### Flujo actual (Avgust hoy)
```
AppSheet Transport Request
    → Base_inicio-def (Google Sheet) — pedidos raw, 1 fila = 1 remisión
    → Bernardo consolida en Control Transporte
    → ASIGNADOS (Google Sheet) — viajes consolidados con proveedor asignado
    → Script genera mail "SOLICITUD DE SERVICIOS"
    → n8n → DETALLE_PEDIDOS + VIAJES_PUBLICOS (Sheets legacy)
    → analizador-rutas.html (lee DETALLE_PEDIDOS via CSV)
```

### Flujo futuro (Supabase como única fuente)
```
Cualquier fuente → n8n Intake Router → tabla pedidos (Supabase)
Bernardo consolida en Netfleet → tabla viajes_consolidados (Supabase)
n8n genera mail desde tabla viajes_consolidados (reemplaza script actual)
analizador-rutas.html lee tabla viajes_consolidados directo (sin mail, sin Sheet)
Google Sheets desaparece completamente
```

### 4 niveles de cliente
```
NIVEL 1 — Email texto libre
  Ejemplo: "necesito mover 500 kg de Bogotá a Cali el viernes"
  Parser: Gmail Trigger → Claude API extrae campos → INSERT pedidos

NIVEL 2 — Google Sheet del cliente
  Ejemplo: cliente con su propio Sheet de pedidos
  Parser: n8n Schedule pull → mapeo columnas → INSERT pedidos

NIVEL 3 — Formulario Netfleet (app web)
  Ejemplo: cliente usa empresa.html o portal dedicado
  Parser: INSERT directo Supabase desde frontend

NIVEL 4 — CRM/API del cliente (Avgust futuro)
  Ejemplo: CRM Avgust dispara webhook con JSON
  Parser: n8n Webhook → validación → INSERT pedidos
```

### Modelo de tablas Supabase

**Tabla `clientes`** — configuración por cliente
```sql
CREATE TABLE clientes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          text NOT NULL,           -- 'AVGUST' | 'FATECO' | 'Cliente Nuevo'
  nit             text,
  email_contacto  text,
  nivel_ingesta   text,                    -- 'email'|'sheet'|'formulario'|'webhook'
  sheet_id        text,                    -- si nivel=sheet: ID del Google Sheet
  sheet_tab       text,                    -- pestaña a leer
  webhook_secret  text,                    -- si nivel=webhook
  email_origen    text,                    -- si nivel=email: filtro remitente
  activo          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now()
);
```

**Tabla `viajes_consolidados`** ← migra desde ASIGNADOS
```sql
CREATE TABLE viajes_consolidados (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_ref           text NOT NULL UNIQUE, -- 'RT-TOTAL-...' generado
  cliente_id          uuid REFERENCES clientes(id),
  fecha_consolidacion timestamptz,
  fecha_cargue        timestamptz,
  empresa             text,
  zona                text,
  origen              text,
  destino             text,
  km_total            numeric,
  flete_total         numeric,
  proveedor           text,
  estado              text DEFAULT 'pendiente',
  -- 'pendiente'|'confirmado'|'en_ruta'|'entregado'|'finalizado'
  cantidad_pedidos    int,
  peso_kg             numeric,
  contenedores        int DEFAULT 0,
  cajas               int DEFAULT 0,
  bidones             int DEFAULT 0,
  canecas             int DEFAULT 0,
  unidades_sueltas    int DEFAULT 0,
  valor_mercancia     numeric,
  tipo_vehiculo       text,
  placa               text,
  conductor_nombre    text,
  conductor_id        text,
  candado             numeric DEFAULT 0,
  cargue_descargue    numeric DEFAULT 0,
  escolta             numeric DEFAULT 0,
  standby             numeric DEFAULT 0,
  itr                 numeric DEFAULT 0,
  observaciones       text,
  fuente              text,               -- 'sheet_asignados'|'netfleet'|'webhook'
  raw_payload         text,
  mes                 int,
  anio                int,
  created_at          timestamptz DEFAULT now()
);
```

**Tabla `pedidos`** ← migra desde Base_inicio-def
```sql
CREATE TABLE pedidos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_id         uuid REFERENCES viajes_consolidados(id), -- NULL hasta consolidación
  cliente_id       uuid REFERENCES clientes(id),
  -- Campos mínimos (cualquier fuente)
  origen           text NOT NULL,
  destino          text NOT NULL,
  fecha_cargue     timestamptz,
  fuente           text NOT NULL,  -- 'email'|'sheet'|'formulario'|'webhook'
  estado           text DEFAULT 'sin_consolidar',
  -- 'sin_consolidar'|'consolidado'|'asignado'|'en_ruta'|'entregado'
  -- Campos enriquecidos (fuentes estructuradas)
  pedido_ref       text,           -- 'RM-00004430' | NULL si email libre
  id_consecutivo   text,           -- 'RT-0002' (ID AppSheet legacy)
  empresa          text,
  zona             text,
  peso_kg          numeric,
  tipo_mercancia   text,
  contenedores     int DEFAULT 0,
  cajas            int DEFAULT 0,
  bidones          int DEFAULT 0,
  canecas          int DEFAULT 0,
  unidades_sueltas int DEFAULT 0,
  valor_mercancia  numeric,
  valor_factura    numeric,
  -- Campos operativos
  cliente_nombre   text,           -- nombre del cliente final (receptor)
  contacto_nombre  text,
  contacto_tel     text,
  direccion        text,
  horario          text,
  llamar_antes     boolean DEFAULT false,
  observaciones    text,
  -- Campos Avgust específicos (nullable para otros clientes)
  vendedor         text,
  jefe_zona        text,
  coordinador      text,
  prioridad        text,
  motivo_viaje     text,
  -- Auditoría
  raw_payload      text,           -- texto/JSON original tal como llegó
  created_at       timestamptz DEFAULT now()
);
```

### 4 parsers n8n a construir

**Parser 1 — Email texto libre** (clientes Nivel 1)
- Trigger: Gmail — filtro por `cliente.email_origen`
- Nodos: Gmail Trigger → Code (detecta cliente) → Claude API (extrae campos) → INSERT pedidos
- Claude prompt: extrae origen, destino, fecha, peso, tipo_mercancia del texto libre

**Parser 2 — Google Sheet pull** (clientes Nivel 2)
- Trigger: Schedule cada hora
- Nodos: Code (itera tabla clientes nivel=sheet) → Google Sheets read → Normalizador → INSERT pedidos (upsert por pedido_ref)

**Parser 3 — Webhook** (clientes Nivel 4 — Avgust futuro CRM)
- Trigger: HTTP Webhook
- Nodos: Webhook → Validar secret → Normalizador → INSERT pedidos

**Parser 4 — Sheet ASIGNADOS pull** (Avgust legacy — migración)
- Trigger: Schedule cada 30 min
- Nodos: Sheets read ASIGNADOS → Normalizador → UPSERT viajes_consolidados → vincular pedidos por CONSECUTIVOS_INCLUIDOS
- Se desactiva cuando Netfleet reemplaza Control Transporte

### Decisiones técnicas tomadas
- `cliente_id` como FK desde el inicio — no texto libre — para escalar limpio
- Campos mínimos obligatorios: `origen, destino, fuente, cliente_id` — resto nullable
- `raw_payload` siempre — permite re-parsear si el parser falla
- Mail sigue siendo canal de notificación al proveedor, NO fuente de datos
- `analizador-rutas.html` migrará a leer tabla `viajes_consolidados` directo — elimina dependencia del CSV
- Google Sheets desaparece gradualmente: Sheets siguen en paralelo hasta que Supabase esté estable
- Avgust futuro: CRM → webhook directo → Nivel 4 (sin intervención manual)

---

## Módulo 4 — Control y Consolidación (diseño completo)

### Visión
Reemplaza **AppSheet Control Transporte** + el Apps Script `procesarConsolidadoTotal`. Es la UI + backend donde un operador Logxie convierte pedidos `sin_consolidar` (Módulo 2) en viajes consolidados listos para subasta. Integra: consolidación, sugerencia de precio Ridge, publicación a Netfleet, mail al proveedor, adjudicación de oferta ganadora, gestión de estados.

### Flujo actual (a reemplazar)
```
AppSheet Control Transporte (Bernardo consolida manual)
  → marca filas en Base_inicio-def → Envio_Temporal (staging)
  → Apps Script procesarConsolidadoTotal
  → ASIGNADOS (Sheet) + PARA BODEGAS + mail bcc a todos los proveedores
```
Problemas: info se pierde al concatenar (observaciones, direcciones, soportes por pedido), no hay audit trail, `RT-TOTAL-{timestamp}` puede colisionar, lógica no-transaccional.

### Flujo futuro (Módulo 4)
```
pedidos sin_consolidar (Supabase, viene de Módulo 2)
  → control.html: operador filtra + selecciona grupo
  → fn_consolidar_pedidos(ids[], metadata) [Postgres, atómica]
  → viaje_consolidado creado, pedidos → estado 'consolidado' con viaje_id
  → Ridge calcula precio sugerido (JS en cliente o fn_estimar_precio)
  → operador ajusta precio si es necesario
  → fn_publicar_viaje(viaje_id) → estado 'pendiente' (listo para subasta)
     ↓                                          ↓
  mail al proveedor con link transportador.html → subasta abierta
  (cualquier transportador logueado oferta, no solo el del mail)
  → ofertas llegan a tabla ofertas (Módulo 1)
  → operador ve ofertas en control.html → clic "Adjudicar"
  → fn_adjudicar_oferta(oferta_id) → viaje 'confirmado', oferta ganadora aceptada, resto rechazadas
  → a partir de acá: estados en_ruta → entregado → finalizado
```

### Usuarios y roles

| Rol | Puede | Cómo |
|---|---|---|
| **Logxie staff** (Bernardo + empleados + LogxIA) | Todo en control.html — ver/consolidar/ajustar precios/adjudicar de cualquier cliente | `perfiles.tipo='logxie_staff'` — RLS acceso total |
| **Cliente BPO** | Nada directamente. Logxie opera por él | No tiene cuenta Supabase. El cliente `clientes.plan_bpo=true` |
| **Cliente self-service** | Ver SUS pedidos + viajes, publicar nuevos pedidos vía formulario (Módulo 2 Nivel 3) | `perfiles.tipo='cliente_self_service'` + `perfiles.cliente_id` FK — RLS filtra por `cliente_id` |
| **Transportador** | Ver viajes publicados, ofertar, ver sus ofertas | Ya existe (Módulo 1) — `perfiles.tipo='transportador'` |

**Nuevas columnas requeridas:**
- `clientes.plan_bpo BOOLEAN NOT NULL DEFAULT false`
- `perfiles.cliente_id UUID REFERENCES clientes(id)` — solo populado para `tipo='cliente_self_service'`
- `perfiles.tipo` check: agregar `'logxie_staff'`, `'cliente_self_service'` (ya existe `'transportador'`, `'empresa'`)

### State machines

**pedidos.estado:**
```
sin_consolidar → consolidado → asignado → en_ruta → entregado → finalizado
               ↘ cancelado            ↘ entregado_novedad | rechazado
(si el viaje se desconsolida/cancela → pedidos vuelven a sin_consolidar)
```

**viajes_consolidados.estado:**
```
(al crear) pendiente → confirmado → en_ruta → entregado → finalizado
                    ↘ cancelado (dispara fn_desconsolidar → pedidos a sin_consolidar)
```

### Postgres functions (capa lógica)

| Function | Input | Output | Qué hace |
|---|---|---|---|
| `fn_consolidar_pedidos(ids UUID[], metadata JSONB)` | Array de pedido_ids + {origen, destino, fecha_cargue, observaciones} | `UUID` (viaje_id nuevo) | Valida que todos sean `sin_consolidar`. Crea viaje con sums agregadas. Updatea pedidos. Transaccional. |
| `fn_desconsolidar_viaje(viaje_id UUID)` | viaje_id | `INT` (# pedidos liberados) | viaje → `cancelado`, pedidos → `sin_consolidar` + `viaje_id=NULL`. Reversa de consolidar. |
| `fn_ajustar_precio_viaje(viaje_id UUID, nuevo_flete NUMERIC, razon TEXT)` | viaje_id + precio + razón | VOID | Updatea `flete_total`, audit trail. Solo antes de publicar. |
| `fn_publicar_viaje(viaje_id UUID)` | viaje_id | VOID | Cambia estado `confirmado → pendiente` (publicado para subasta). Dispara email (vía trigger o webhook). |
| `fn_adjudicar_oferta(oferta_id UUID)` | oferta_id | VOID | Oferta → `aceptada`. Resto de ofertas del mismo viaje → `rechazada`. Viaje → `confirmado`. `proveedor` en viaje queda seteado. |
| `fn_estimar_precio_viaje(viaje_id UUID)` | viaje_id | `NUMERIC` | Llama al Ridge con km, kg, paradas, zona, origen del viaje. Devuelve sugerencia. Opcional portar desde JS. |

### UI — `control.html` (nuevo)

**Tabs:**
1. **Pedidos sin consolidar** — listado con filtros (cliente, zona, fecha, origen, destino, peso). Checkboxes. Botón "Consolidar seleccionados" → modal.
2. **Viajes en subasta** — viajes en estado `pendiente` con contador de ofertas. Clic → ver detalle + ofertas. Botón "Adjudicar" por oferta.
3. **Viajes activos** — estados `confirmado`, `en_ruta`, `entregado`. Tracking + cumplidos.
4. **Historial** — viajes `finalizado` y `cancelado`. Auditoría.

**Modal "Consolidar seleccionados":**
- Preview de lo que se va a agregar (sums, ruta consolidada)
- Campos editables: origen_consolidado, destino_consolidado, fecha_cargue, observaciones
- Muestra precio Ridge sugerido → editable (razón requerida si se cambia)
- Botón "Crear y publicar" (ejecuta `fn_consolidar` + `fn_ajustar_precio` + `fn_publicar` en secuencia)
- Botón "Crear sin publicar" (solo consolidar, publicar después)

### Audit trail — tabla `acciones_operador`
```sql
CREATE TABLE acciones_operador (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES auth.users(id),
  accion       text NOT NULL,  -- 'consolidar' | 'desconsolidar' | 'ajustar_precio' | 'adjudicar' | 'cancelar'
  entidad_tipo text NOT NULL,  -- 'viaje' | 'pedido' | 'oferta'
  entidad_id   uuid NOT NULL,
  metadata     jsonb,          -- snapshot de la acción (antes/después, razón)
  created_at   timestamptz NOT NULL DEFAULT now()
);
```
Las Postgres functions escriben esta tabla como parte de su transacción. Sirve para: "¿quién cambió el precio del viaje X?", "¿cuándo se desconsolidó?".

### Integración email con link Netfleet

- Supabase Edge Function `send_viaje_mail(viaje_id)` o webhook n8n
- Template HTML similar al Apps Script actual (misma estructura que los proveedores conocen)
- Link al final: `https://netfleet.app/transportador.html?viaje_ref=RT-TOTAL-xxx` → scroll/highlight de ese viaje
- Requiere proveedor SMTP (Resend, SendGrid, Gmail API con OAuth) — decisión pendiente

**Deep-linking en transportador.html**: requiere leer `?viaje_ref=` de la URL, hacer scroll al viaje y resaltarlo. Cambio chico.

### Decisiones técnicas tomadas

- **Consolidación transaccional**: todo en Postgres function única, rollback automático si falla.
- **Precio Ridge sugerido no vinculante**: operador puede ajustar antes de publicar (razón queda en audit).
- **Subasta abierta**: cualquier transportador logueado oferta. El mail es notificación, no restricción.
- **Desconsolidar = cancelar**: misma función (`fn_desconsolidar_viaje`). Semánticamente: cancelar es desconsolidar con intención de no rehacer; desconsolidar es sacar pedidos para reagrupar.
- **Cancelar pedidos individuales** (no el viaje entero): NO soportado en primera versión. Hay que desconsolidar el viaje completo.
- **RLS por rol**: Logxie staff acceso total; cliente_self_service filter por `cliente_id`; transportador ve ofertas + viajes publicados.
- **Viajes multi-empresa**: si el operador agrupa pedidos de AVGUST + FATECO en un viaje, el viaje queda con `cliente_id=NULL` y `empresa='AVGUST, FATECO'`. Los pedidos conservan su `cliente_id` individual.
- **Orden de construcción**: (1) schemas + functions → (2) UI control.html → (3) email → (4) test E2E con 50 pedidos.

### Pendientes del Módulo 4

- [x] ✅ hecho 2026-04-17 — **Schema updates**: `clientes.plan_bpo` (AVGUST+FATECO = true), tabla `perfiles` creada desde cero con `cliente_id` FK y CHECK `tipo IN (transportador|empresa|logxie_staff|cliente_self_service)`, trigger `handle_new_user` + helper `is_logxie_staff()`. Ver [db/perfiles.sql](db/perfiles.sql) + [db/modulo4_schema.sql](db/modulo4_schema.sql). **Nota:** la tabla `perfiles` no existía en Supabase a pesar de estar documentada — 3 usuarios en `auth.users` sin fila correspondiente. Los frontends venían tirando 404 silencioso contra `/rest/v1/perfiles` desde siempre.
- [x] ✅ hecho 2026-04-17 — **Tabla `acciones_operador`** + 4 índices + RLS (staff lee via `is_logxie_staff()`, service_role full). Ver [db/modulo4_schema.sql](db/modulo4_schema.sql).
- [x] ✅ hecho 2026-04-17 — **Tablas `transportadoras` + `ofertas` + `invitaciones_subasta`**: 7 transportadoras seed (ENTRAPETROL, TRASAMER, JR, Nueva Colombia, PRACARGO, Global, Vigía), `ofertas` con RLS (usuario ve las suyas + staff ve todo), `invitaciones_subasta` para subastas cerradas. Ver [db/modulo4_schema_extra.sql](db/modulo4_schema_extra.sql).
- [x] ✅ hecho 2026-04-17 — **ALTER `viajes_consolidados`**: +6 columnas (`subasta_tipo`, `publicado_at`, `adjudicado_at`, `oferta_ganadora_id`, `adjudicacion_tipo`, `transportadora_id`). CHECK de `acciones_operador.accion` extendido con `agregar_pedido`, `quitar_pedido`, `invitar`, `asignar_directo`.
- [x] ✅ hecho 2026-04-17 — **9 Postgres functions** + helper `_recalc_viaje_agregados`: `fn_consolidar_pedidos`, `fn_agregar_pedido_a_viaje`, `fn_quitar_pedido_de_viaje`, `fn_desconsolidar_viaje`, `fn_ajustar_precio_viaje`, `fn_publicar_viaje`, `fn_invitar_transportadora`, `fn_asignar_transportadora_directo`, `fn_adjudicar_oferta`. Todas `SECURITY DEFINER` + gate `is_logxie_staff()` + audit a `acciones_operador`. Ver [db/modulo4_functions.sql](db/modulo4_functions.sql). `viaje_ref` ahora genera formato `NF-YYMMDD-HHMMSS-XXXX`.
- [x] ✅ hecho 2026-04-17 — **control.html** con 4 tabs (sin_consolidar / subasta / activos / historial). Auth gate por `perfiles.tipo='logxie_staff'`. Invoca las 9 functions vía `/rest/v1/rpc/*`. Modales: consolidar (+ Ridge sugerido + publicar inline con tipo abierta/cerrada), ajustar_precio, asignar_directo. Adjudicar y desconsolidar inline desde cards de viaje. Ver [control.html](control.html). Smoke test SQL validado end-to-end (consolidar→ajustar→publicar→adjudicar + 4 rows de audit, ROLLBACK limpio). Ver [db/smoke_test_modulo4.sql](db/smoke_test_modulo4.sql).
- [x] ✅ hecho 2026-04-17 — **`fn_reabrir_viaje(viaje_id, razon)`**: revierte viaje `confirmado → pendiente`, libera proveedor y adjudicación, pedidos vuelven a `consolidado`, ofertas reactivadas si era subasta. Botón "↩ Reabrir" en cards de tab Activos. Ver [db/modulo4_reabrir.sql](db/modulo4_reabrir.sql).
- [x] ✅ hecho 2026-04-17 — **control.html improvements iterativos**: auto-switch de tab tras cada acción (adjudicar→Activos, reabrir→Consolidados, etc.), toasts descriptivos con proveedor, agrupar sin_consolidar por origen + checkbox grupo, filtro fechas desde/hasta + presets 7d/30d/90d, prioridad badge (URGENTE rojo, ALTA naranja, NORMAL azul), llamar_antes flag, modal detalle completo de pedido (embalaje/contacto/dirección/horario/observaciones), sección "Pedidos incluidos" expandible dentro de viaje cards, stats por viaje ($/kg, $/km, $/pedido, %flete-vs-valor rojo si >3%), 2 filas de aggregates en tab Consolidados, tags 🏆 subasta / 📌 directa en Activos, badge "borrador" + botón Publicar en cards no publicadas, RLS clientes ahora permite read/write a logxie_staff.
- [x] ✅ hecho 2026-04-19 — **Sync Sheets→Netfleet unidireccional**: `fn_sync_viajes_batch(jsonb)` + `fn_sync_pedidos_batch(jsonb)` con UPSERT idempotente, reglas (Netfleet gana / terminales skip / cancelado propaga), audit. Helper `_norm_empresa()` canonicaliza variantes ("FATECO, AVGUST" → "AVGUST, FATECO") automáticamente en cada sync. Script Python [db/sync_from_csv.py](db/sync_from_csv.py) lee CSV exports de Sheets y llama RPCs en batches de 500, soporta `--truncate`. Ver [db/modulo4_sync.sql](db/modulo4_sync.sql) + [db/modulo4_norm_empresa.sql](db/modulo4_norm_empresa.sql).
- [x] ✅ hecho 2026-04-19 — **Backfill inicial fresh**: TRUNCATE + sync completo desde CSVs (1281 viajes + 3740 pedidos, 94.7% linkeados). 82 filas con empresa "FATECO, AVGUST" normalizadas a "AVGUST, FATECO".
- [x] ✅ hecho 2026-04-20 — **Fase 1 Pipeline — Tab Nuevos + revisión de pedidos**: ALTER pedidos +revisado_at/revisado_por/revision_notas + 2 índices parciales. `fn_marcar_revisado` + `fn_marcar_no_revisado`. Backfill: 3740 pedidos históricos marcados como revisados (no aparecen en Nuevos). Warning visual ⚠ si falta origen/destino/peso/cliente. Ver [db/modulo4_revision_pedidos.sql](db/modulo4_revision_pedidos.sql).
- [x] ✅ hecho 2026-04-20 — **Cerrar viajes bulk + paginación fix**: `fn_cerrar_viaje` + `fn_cerrar_viajes_batch` (→ finalizado). `getJsonPaginated` con Range header — fix crítico del cap 1000 de PostgREST (antes solo veías 500/499 activos/historial de 1281). Paginación estable con `id.desc` secondary sort. Ver [db/modulo4_cerrar_viaje.sql](db/modulo4_cerrar_viaje.sql).
- [x] ✅ hecho 2026-04-20 — **`fn_reabrir_finalizado(id, razon)`**: revierte cierre (finalizado → confirmado, pedidos entregado → asignado). Botón "↩ Deshacer cierre" en cards de Historial. Ver [db/modulo4_reabrir_finalizado.sql](db/modulo4_reabrir_finalizado.sql).
- [x] ✅ hecho 2026-04-20 — **Tab Pedidos unificado con admin completo**: elimina tab Nuevos separado (ahora filtro virtual). 7 pills de estado multiselect + filtros `🔗 Sin viaje` y `⚠ Inconsistentes` con bypass. Bulk actions: Cancelar, Resetear, Volver a Nuevos, Cambiar estado (forzar), Eliminar (DELETE hard con snapshot). Modal Editar con 28 campos. Botones por fila: ℹ detalle, ✎ editar, ⎘ clonar para reintento. Functions: `fn_pedidos_cancelar_batch`, `fn_pedidos_resetear_batch`, `fn_pedido_clonar`, `fn_pedido_editar`, `fn_pedidos_cambiar_estado_batch`, `fn_pedidos_eliminar_batch`. Ver [db/modulo4_pedidos_bulk.sql](db/modulo4_pedidos_bulk.sql) + [db/modulo4_pedidos_admin.sql](db/modulo4_pedidos_admin.sql).
- [x] ✅ hecho 2026-04-20 — **Linker v3 CORREGIDO**: parser entiende que `-` y `/` dentro de un token son ALIASES del mismo pedido (no rangos). Separador real de pedidos = `,`. Fix espacios alrededor de dashes ("TI -00001968" → TI-1968). Ver [db/link_pedidos_viajes_v3.sql](db/link_pedidos_viajes_v3.sql).
- [x] ✅ hecho 2026-04-20 — **Linker v4 substring (BUSCARX-style)**: replica la fórmula de Bernardo `=BUSCARX("*"&ref&"*"; PEDIDOS_INCLUIDOS; ID_CONSOLIDADO)` en SQL. Corre DESPUÉS de v3 como segundo pase para rescatar huérfanos. Guardrails: refs ≥5 chars, solo matches únicos. Resultado cascada v3+v4: **97.3% linked** (3647/3748). Ver [db/link_pedidos_viajes_v4.sql](db/link_pedidos_viajes_v4.sql).
- [x] ✅ hecho 2026-04-20 — **Kanban Fase 1 en control.html**: nav 3 workspaces (🏠 Inicio / 📥 Pedidos / 🚚 Viajes) + sub-nav de Viajes (Por asignar / En ruta / Archivo). Tab Inicio con 6 tarjetas KPI clickeables (dashboard orientado a customer journey). Verb naming en tabs. Counts totales absolutos. Ver commits `bd640f5`, `6cf370d`, `7c13398`.
- [x] ✅ hecho 2026-04-20 — **sync_from_csv.py robusto**: detección automática de encoding (utf-8-sig → cp1252 → latin-1 para Excel Windows ES) + delimiter (, vs ;). Warning si abrís CSV con Excel — corrompe formato.
- [x] ✅ hecho 2026-04-20 — **Re-sync fresh con Sheet actual**: 1297 viajes + 3748 pedidos + 88.4% linked. Linker v3 resolvió sobrelinkeos previos (ej. RT-TOTAL-1776311734125 pasó de 46 → 26 correctos).
- [x] ✅ hecho 2026-04-20 — **Kanban Fase 1** (dashboard Inicio + 3 workspaces + sub-nav Viajes + verb naming). Fase 2 (kanban columnas horizontales + drag&drop) pendiente para otra sesión.
- [ ] **n8n workflow cron 15min + webhook manual** — llama `fn_sync_viajes_batch` y `fn_sync_pedidos_batch` con data del Google Sheets API. Opcional: publicar pestañas como CSV URL (Archivo → Compartir → Publicar en la Web) y fetch directo, o usar credencial `IuCNLIa09oW4ZWBu` de n8n.
- [ ] **Botón 🔄 Sync en control.html** — header nav, POST al webhook n8n, toast con counters.
- [x] ✅ hecho 2026-04-22 — **Deep-linking** implementado en `mi-netfleet.html` (ver arriba).
- [ ] **Integración email**: elegir proveedor + Edge Function o n8n webhook para publicar/invitar/adjudicar
- [x] ✅ hecho 2026-04-22 — **Workspace Catálogo en control.html** con CRUD de Clientes y Transportadoras (soft delete, filtros, contadores vinculados). Falta solo la sub-tab 👥 Usuarios staff (placeholder — requiere Edge Function con service_role para crear auth.users).
- [ ] **Data quality**: revisar los 434 huérfanos actuales. Muchos son refs typeados mal en el Sheet (ej. `RM-70325 - 73028` era `RM-73025 - 73028`), rangos cross-prefix imposibles, o placeholders tipo `DEVOLUCION`. Limpiar en AppSheet para que el próximo sync resuelva.
- [x] ✅ hecho 2026-04-17 — **Migración de operadores**: Bernardo ya es `logxie_staff aprobado` en perfiles (id: fa822bae-4743-4d40-95cf-c9fdd815214f). Los otros 2 auth.users son `transportador pendiente`. Pendiente: crear cuentas para empleados Logxie (vía Admin tab futura).
- [ ] **RLS en `viajes_consolidados`**: hoy `authenticated_all` es muy permisivo. Endurecer para que transportadoras solo vean viajes con `subasta_tipo='abierta'` o invitaciones vigentes en `invitaciones_subasta`. Deferido hasta que auth de transportadoras esté validado.
- [ ] **Tabla `leads`/`cargas`**: no existen en Supabase (son Módulo 1, fuera de alcance M4). Diferido.

---

## Lo que NUNCA se toca sin instrucción explícita

Funciones `cc*` (pricing) · `obtenerRutaOSRM()` · `initMapa()` · `cargarViajes()` · `renderViajes()` · `seleccionarViaje()` · toda la lógica de Supabase · autenticación · modales de oferta · `supabase.min.js` · cualquier query a la DB · `beacon.min.js` de Cloudflare Analytics
