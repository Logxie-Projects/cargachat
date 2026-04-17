# NETFLEET + LOGXIA — Fuente de Verdad
> Logxie Connect S.A.S. · Bernardo Aristizabal · bernardoaristizabal@logxie.com · +573214401975

---

## Cómo arrancar una sesión nueva

- **Claude Code:** este archivo se carga automáticamente al abrir el repo en `D:\NETFLEET`
- **Claude chat:** adjuntar este archivo o escribir "lee CLAUDE.md y continuemos"
- **Al terminar cada sesión:** actualizar sección Pendientes con decisiones tomadas

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
├── mis-ofertas.html            → Vista ofertas del transportador
├── viaje.html                  → Tarjeta individual (screenshots LinkedIn)
├── checkderuta.html            → Módulo seguimiento de ruta en tiempo real
├── analizador-rutas.html       → Planificación de entregas por viaje consolidado
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
├── /db/                        → Schemas SQL Supabase
│   └── ofertas.sql
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

### Tabla `viajes` (pendiente crear)
Migración futura desde Google Sheets CSV.

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
- **Google Sheets como fuente transitoria:** se mantiene mientras no exista tabla `viajes` en Supabase
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
| 2 | Ingesta multicliente | AppSheet Transport Request | En diseño — arquitectura definida, SQL en /db/ |
| 3 | Seguimiento y cumplidos | Donde Está mi Pedido + Navegador | Pendiente |
| 4 | Control y consolidación | Control Transporte + script Sheets | Pendiente — LogxIA decide consolidación a futuro |
| 5 | Analytics | DATA UNIFICADA + Looker Studio | Pendiente |

---

## Pendientes Prioritarios

### 🔥 Seguridad
- [ ] **Rotar Anthropic API key** en [console.anthropic.com](https://console.anthropic.com/settings/keys) — quedó en texto plano en `LogxIA/CLAVES Y APIS.txt` antes de gitignorarla. Asumir comprometida.
- [ ] **Rotar Telegram bot token** en `@BotFather` → `/revoke` → `/token`

### Refactor — Paso 2
- [ ] **Unificar las 5 copias de CIUDADES/estimarPrecio** en `netfleet-core.js` + `<script src="netfleet-core.js">` en cada HTML. Borrar copias locales.

### Producto
- [ ] **Renombrar** `LogxIA — PRODUCCIÓN v2 (Mails Avgust)` → `LogxIA — Parser Detalle Pedidos` en n8n
- [ ] **LogxIA:** agregar Vigía y Global Logística al diccionario `CORREOS_PROVEEDORES` en Seguimiento Transportadores
- [ ] **LogxIA:** poblar `ADMIN_IDS` y arrays de Telegram IDs por proveedor en Bot Telegram
- [ ] **transportador.html:** rediseño — viajes públicos sin login, registro 2 pasos al ofertar
- [ ] **Reactivar LinkedIn** en workflow LinkedIn+Viajes — cambiar URL Screenshotone a `netfleet.app`
- [ ] **Renombrar repo** `cargachat` → `netfleet` en GitHub (reapuntar Cloudflare Pages primero)
- [ ] **Tabla `viajes` Supabase:** migrar de Google Sheets CSV
- [ ] **empresa.html:** formulario publicación de carga → Supabase tabla `viajes`
- [ ] **og-image.png:** 1200×630px para preview WhatsApp/LinkedIn
- [ ] **Módulo 2 — Ingesta Multicliente:** ejecutar `clientes.sql` + `viajes.sql` + `pedidos.sql` en Supabase, luego construir 4 parsers n8n
- [ ] **LogxIA Módulos 3-5:** Consolidación inteligente, Pricing dinámico, Predicción de demanda

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
Bernardo consolida en Netfleet → tabla viajes (Supabase)
n8n genera mail desde tabla viajes (reemplaza script actual)
analizador-rutas.html lee tabla viajes directo (sin mail, sin Sheet)
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

**Tabla `viajes`** ← migra desde ASIGNADOS
```sql
CREATE TABLE viajes (
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
  viaje_id         uuid REFERENCES viajes(id), -- NULL hasta consolidación
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
- Nodos: Sheets read ASIGNADOS → Normalizador → UPSERT viajes → vincular pedidos por CONSECUTIVOS_INCLUIDOS
- Se desactiva cuando Netfleet reemplaza Control Transporte

### Decisiones técnicas tomadas
- `cliente_id` como FK desde el inicio — no texto libre — para escalar limpio
- Campos mínimos obligatorios: `origen, destino, fuente, cliente_id` — resto nullable
- `raw_payload` siempre — permite re-parsear si el parser falla
- Mail sigue siendo canal de notificación al proveedor, NO fuente de datos
- `analizador-rutas.html` migrará a leer tabla `viajes` directo — elimina dependencia del CSV
- Google Sheets desaparece gradualmente: Sheets siguen en paralelo hasta que Supabase esté estable
- Avgust futuro: CRM → webhook directo → Nivel 4 (sin intervención manual)

---

## Lo que NUNCA se toca sin instrucción explícita

Funciones `cc*` (pricing) · `obtenerRutaOSRM()` · `initMapa()` · `cargarViajes()` · `renderViajes()` · `seleccionarViaje()` · toda la lógica de Supabase · autenticación · modales de oferta · `supabase.min.js` · cualquier query a la DB · `beacon.min.js` de Cloudflare Analytics
