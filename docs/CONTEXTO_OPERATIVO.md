# Estado actual Netfleet

> Foto del proyecto al **2026-04-22 (sesión tarde/noche — journey mapping + scenarios + analizador Supabase)**.
>
> **Lo nuevo vs. cierre anterior:** capa de **Scenarios** operativa (propuestas tentativas de viaje — un pedido puede vivir en N scenarios sin salir de `sin_consolidar` hasta que se promueva uno). Analizador-rutas migrado a Supabase con selector dual 🚚 Viaje / 🧪 Scenario + deep-link `?scenario=<id>`. Badge de zona color inline + sub-split automático por zona dentro de "Agrupar por Origen". Nuevo doc [LOGXIA_JOURNEY.md](LOGXIA_JOURNEY.md) con tabla journey 7 pasos × [hoy · Fase 1 · Fase 2 · Fase 3], reglas Fase 1 priorizadas y spec de sistema de rating + Módulo 6 Facturación.
>
> **Lo que sigue en producción del cierre anterior:** Panel control reestructurado como "panel de trabajo" orientado a autopilot (tab Inicio en 2 bloques con badges de piloto, tab Pedidos con tira de pistas + agrupado por RUTA + hints, tab Viajes (subasta + activos) con el mismo framing, workspace 🏢 Catálogo con CRUD de clientes y transportadoras, ofertas visibles, Drive API operativo para cumplidos). Portal `mi-netfleet.html` con login inline + 5 stats KPI + deep-link `?viaje_ref=`.

## TL;DR de la sesión 2026-04-22 (tarde/noche)

### Journey mapping + reglas autopilot
- Recorrido lineal con Bernardo de los 7 pasos operativos + 3 pasos invisibles (intake, consolidar, post-cierre). Salió el dato calibrador: **20% de pedidos nuevos tienen el mismo bug** — destino↔dirección swap cuando el vendedor pone el destino real en `direccion` porque no está en catálogo. ~80 h/año recuperables con regla #1 de Fase 1.
- **Insight de subasta**: no es solo minimizar precio — es broadcast + price discovery (descubrir precio para facturar a Avgust). Eso condiciona el autopilot: no auto-adjudicar al más bajo sin preservar ancla de mercado.
- **Sistema de calificación acordado** (3 actores × 6 dimensiones al cerrar viaje, visible a transportadoras). Fase 0 implícito = calcular desde datos existentes sin input humano.
- **Módulo 6 Facturación** — nuevo módulo fuera del roadmap original: portal `cliente.html` para Avgust (ve cumplidos + facturas) + tab "💰 Facturar" en mi-netfleet (gate cumplidos 100%).
- Spec completa en [docs/LOGXIA_JOURNEY.md](LOGXIA_JOURNEY.md).

### Scenarios (capa tentativa de consolidación)
- **Problema que resuelve:** cuando Bernardo armaba combinaciones tentativas, los pedidos desaparecían de `sin_consolidar` y no podía seguir "jugando" con ellos.
- **Solución:** entidad `scenarios_viaje` = propuesta tentativa. Un pedido puede estar en N scenarios mientras siga en `sin_consolidar`. Solo al **promover** un scenario se crea el viaje real y los otros que compartían pedidos quedan `conflictivo` (con mensaje claro: "tiene N pedidos ya consumidos — limpiar o descartar"). `fn_scenario_limpiar_consumidos` quita los consumidos y devuelve a `borrador` con los libres.
- Backend: 2 tablas + 6 Postgres functions + RLS staff-only. Smoke test PASS end-to-end. Ver [db/scenarios_viaje.sql](../db/scenarios_viaje.sql).
- UI control.html: sub-tab **🧪 Scenarios** (count = borrador + conflictivo), cards con estado + agregados + warnings + acciones contextuales (Promover → abre modal pre-cargado / Descartar / Limpiar / Quitar pedido individual). Action-bar Pedidos con 2 botones: **🧪 Crear scenario** (default) + **⚡ Consolidar directo** (escape hatch naranja). Badge `🧪 N` en fila de pedido (rojo si alguno conflictivo).
- Probado en prod por Bernardo — workflow correcto.

### Analizador-rutas migrado a Supabase
- Lee `viajes_consolidados` + `scenarios_viaje` + `scenarios_viaje_pedidos` + `pedidos` en vez del CSV legacy.
- Selector dual en sidebar: **🚚 Viaje existente | 🧪 Scenario tentativo**. Label del select cambia según modo.
- Deep-link: `?scenario=<id>` → auto-setea modo scenario + selecciona; `?viaje=<id>` → equivalente en modo viaje.
- Fallback `?legacy=1` usa el CSV DETALLE_PEDIDOS (por si Supabase cae).
- Parser simple del campo `horario` texto libre → extrae v1_desde/hasta y v2_desde/hasta (patrones `L-V 8:00-17:00`, `L-S 7:30 a 15:00`, etc.). Fallback default 08:00-17:00 si no parsea.
- Adaptador mantiene la estructura "trip" que el analizador ya esperaba — toda la lógica OSRM, Leaflet, cálculo de ETAs y PDF export queda intacta.
- Botones "🗺 Analizar ruta" en scen-card-actions: borrador/conflictivo → `?scenario=<id>`; promovido → `?viaje=<promovido_a_viaje_id>`.
- Requiere sesión staff activa (usa `sb.auth.getSession()`). Si no hay, muestra "Iniciá sesión en control.html primero".

### Badge zona + sub-split zona (mejoras tab Pedidos)
- **Badge zona inline** junto al destino en cada fila: `CHOCONTA [BOYACÁ]`, `PASTO [SUR]`. 13 colores canónicos (BOYACÁ=ámbar, VALLE=rojo, SUR=verde, etc.).
- **Sub-split automático por zona** dentro de cada grupo cuando está en modo "Agrupar por Origen": el grupo `CENTRO 3PL FUNZA` se parte en `BOYACÁ (3)` + `TOLIMA/HUILA (1)` + `SUR (1)`, cada sub-grupo con sus sub-totales + su propio hint contextual ("💡 3 listos — buen candidato" / "⏳ 1 listo — esperar más"). Elimina filtrado mental del operador.
- Helpers: `normalizarZona()` (slug sin tildes ni espacios) + `badgeZona()` (devuelve HTML del span).

## TL;DR de la sesión 2026-04-22 (mañana — en producción)

### Panel control (control.html) — panel de trabajo orientado a autopilot

- **Tab Inicio rediseñado en 2 bloques + badges de piloto**:
  - 📥 PEDIDOS (unidad atómica): Revisar nuevos 🟡, Listos para consolidar 🟢, Con novedad 🔴
  - 🚚 VIAJES (consolidación): Borradores 🟡, Publicados sin proveedor 🟢, En ruta 🟢, Entregados pendiente cerrar 🟢
  - Cada tile con badge 🟢/🟡/🔴 (rutina / supervisada / decisión humana) + tooltip explicando qué puede manejar LogxIA cuando se active autopilot. Ya documenta la arquitectura para cuando llegue la capa IA.
  - KPI nuevo "Con novedad" — pedidos con intento fallido + devuelto_bodega + entregado_novedad.
  - Alert pulse verde en KPI "Publicados sin proveedor" cuando hay ofertas pendientes de adjudicar.

- **Tab Pedidos con tira de pistas + agrupación inteligente**:
  - Tira compacta arriba: chips clickeables con counts globales `🟡 N revisar · 🟢 N listos · 🔴 N con novedad`. Al click filtra la tabla.
  - Selector "Agrupar por" con 3 modos: **Ruta (default, origen→destino)**, Origen, Destino. La ruta es la vista que Bernardo pidió para detectar patrones de consolidación manualmente.
  - Cada grupo muestra sub-totales por estado: `4 nuevos · 10 listos · 5 en ruta · 2 entregados · 1 novedad`.
  - Hint contextual por grupo: `💡 N listos — buen candidato para consolidar` (≥3 listos + ≥500kg), `💡 se puede armar viaje` (≥2), `⏳ esperar más` (1).
  - Grupos ordenados: consolidables arriba (más "listos" primero).

- **Tab Viajes (subasta + activos) con framing LogxIA**:
  - Pistas arriba del tab Subasta: `✏️ N borradores · 💰 N con ofertas · 🤝 N sin ofertas · ⏳ N stale +2d`.
  - Pistas arriba del tab Activos: `📍 N esperando cargue · 🚛 N en ruta · 📬 N listos cerrar · ⚠️ N con novedad`.
  - Hint contextual por card: "Borrador falta publicar", "Publicado hace Xh esperando ofertas", "+Xd sin ofertas — revisar precio", "💰 N ofertas — adjudicar", "Esperando cargue", "En ruta", "Listo para cerrar".
  - Ofertas visibles: cards con ofertas tienen borde verde + banner prominente `N ofertas recibidas · mejor $XXX · clic para adjudicar`.
  - Bloque de tracking visible sin expandir en viajes activos (confirmado/en_ruta/entregado): timeline de 4 steps con check verde si se completó, lista de pedidos con badge individual de estado, link 📷 Foto / 📄 PDF directo al cumplido.

- **Workspace nuevo 🏢 Catálogo** con 3 sub-tabs:
  - 🏭 Clientes: CRUD completo (nombre, NIT, email, nivel ingesta, plan BPO, sheet_id, webhook_secret), conteo de pedidos, soft delete via `activo=false`.
  - 🚛 Transportadoras: CRUD (nombre, NIT, contactos, zonas operadas, tipos vehículos, notas), conteo de viajes asignados, soft delete.
  - 👥 Usuarios staff: placeholder (requiere Edge Function con service_role para crear auth.users).
  - RLS ya permite `staff_all` en ambas tablas.

- **Drive API para cumplidos — 1 clic directo al archivo**:
  - Proyecto Cloud dedicado **NETFLEET** con API key nueva (`AIzaSyBo3eh8YWuP-tdcIYBl_NbWxjqATTa5Tyc`), restringido a Drive API + referrers netfleet.app/* + localhost.
  - Las 2 folders de Avgust `192ritQ72WChqjWwOvO2TTlOvqmbwa8uq` y `17QmlbCaMhlbgYO88G9mLDQ9R4rv1Gm3Y` compartidas "Anyone with the link".
  - `resolverCumplidosAsync` consulta cada folder por separado (OR en single query da 403 con API key sin OAuth), cachea filename→fileId, devuelve URL `drive.google.com/file/d/<id>/view`.
  - Re-render silencioso de Activos + Historial cuando terminan las lookups.

### Portal transportadora (mi-netfleet.html)

- **Login inline (no redirect a landing)**: la URL `netfleet.app/mi-netfleet` se puede compartir con transportadoras directamente; si no hay sesión muestra un card de login con marketing discreto (h1 + 3 bullets de valor) en vez de redirigir a `transportador.html`.
- **Deep-link `?viaje_ref=<ID>`**: al abrir con ese param, scroll a la card + pulse highlight + auto-abre modal de oferta si el transportador está logueado y no ofertó antes.
- **5 stats KPI personalizados**: Viajes con Netfleet, Km recorridos, Facturado (SUM flete_total finalizados), CO₂ evitado (fórmula EPA × 25% ahorro consolidación), Peso transportado. Filtrados por `proveedor ILIKE %empresa%`.
- **Tabs agrupados en 3 bloques**: OFERTAS (Ofertar · Mis ofertas) · SEGUIMIENTO (Mis viajes · Flota) · CUENTA (Facturar · Documentos).
- **Cards de viaje con altura pareja** (flex column + min-height 340px + footer `margin-top:auto`).
- **Tab 🚛 Flota placeholder** — 2 cards (Conductores · Vehículos) con lista de docs por industria (curso sustancias peligrosas para agroquímicos, tarjeta propiedad + tecno + póliza para vehículos). Botón "Gestionar" disabled hasta que se construya el schema.
- **Bug ofertas legacy arreglado**: la tabla ofertas en Supabase fue recreada por el Módulo 4 con `viaje_id UUID FK`, el frontend legacy todavía enviaba `viaje_rt TEXT + nombre/empresa/telefono`. Resolvemos `rt_total → supa_id` antes del INSERT.

## TL;DR de la sesión 2026-04-21

- **Sync completo Sheets → Supabase** funcional (4 pasos, ~30s): `fn_sync_viajes_batch` (ASIGNADOS), `fn_sync_pedidos_batch` (Base_inicio-def), `fn_run_linkers` (v3+v4), `fn_sync_pedidos_seguimiento_batch` (Seguimiento). Cleanup ghosts auto integrado.
- **`id_inicio` como llave estable** de AppSheet — eliminó huérfanos por rename en el Sheet. Migración fresca aplicada.
- **Intentos de entrega + devolución a bodega** — tabla `intentos_entrega` (hasta 3 intentos/pedido), estado nuevo `devuelto_bodega` (después de 3 fallidos), trigger auto de estado del pedido desde intentos. Reemplaza parcialmente el Módulo 3 (data ya fluye de la app "Donde Está mi Pedido" via el Sheet Seguimiento).
- **Timestamps de tracking** (`salida_cargue`, `llegada_descargue`, etc.) sincronizados a nivel viaje. Trigger auto-deriva el estado del viaje (`salida_cargue` set → `en_ruta`; todos pedidos terminales + entregados → `entregado`).
- **transportador.html migrado** — ya no usa el CSV VIAJES_LANDING, lee directo de `viajes_consolidados` filtrado a `estado=pendiente + proveedor vacío`. Autofill de km_total via haversine (persistido en BD por el primer cliente logueado que lo calcula, vía `fn_autofill_km_viaje`). tipo_mercancia='Químico' para AVGUST/FATECO.
- **Estado nuevo `por_revisar`** en pedidos — bucket operativo para pedidos que salen de Nuevos pero no están listos para consolidar. Pill 🔍 Por revisar.
- **Layout 3 columnas en viaje card** de control.html: Col 1 RT+proveedor+flete+estado+fecha; Col 2 ruta+stats; Col 3 chips de pedidos con color por estado. Info rica sin expandir.
- **Resolvedor foto cumplido** abre Drive search por filename (2 folders compartidas públicas). Pending: Drive API para link directo al archivo.
- **Sub-tab renombrado**: "En ruta / seguimiento" → "Asignados". Stats cards clickeables en Activos + Subasta (filtros rápidos).
- **Cleanup ghosts** auto en sync: viajes pendientes sin proveedor que ya no están en el CSV se cancelan (reemplaza el "delete en cascada" que el sync no hacía).
- **Sync monetario en terminales**: viajes finalizados/cancelados actualizan solo flete/peso/valor desde el Sheet, sin resucitar.
- **Botón "↩ Resucitar"** para cancelados en tab Archivo (`fn_reabrir_cancelado`).
- **Agregado regex standard** — BL (Bills of Lading importación) + tolerancia a espacios `RM 67705`.

---

## Qué está en producción hoy

### Sitio live — `netfleet.app`
- **Landing del generador** (`index.html`) con hero + mini-calculadora + mini-mapa + viajes públicos + calculadora completa.
- **Portal empresas** (`empresa.html`) registro/login conectado a Supabase.
- **Dashboard transportador** (`transportador.html`) con listado de viajes, ofertas, documentos.
- **Admin Logxie** (`admin.html`) aprobar/rechazar cuentas.
- **Mis ofertas** (`mis-ofertas.html`) tabs activas/historial.
- **Check-in ruta** (`checkderuta.html`) con webhook n8n.
- **Analizador rutas** (`analizador-rutas.html`) multi-parada.
- **Control staff** (`control.html`) — Módulo 4 UI en producción y en uso por Bernardo.

#### control.html — features actuales (2026-04-20 tarde)

**Nav (3 workspaces + sub-nav en Viajes)**:
```
[ 🏠 Inicio ]  [ 📥 Pedidos ]  [ 🚚 Viajes ]
                                     ↓ (al click)
                                     [🤝 Por asignar] [🚛 En ruta] [📚 Archivo]
```

- Total Pedidos y total Viajes visibles en contadores de las tabs principales (3.748 / 1.297)
- Contadores internos de sub-tabs por estado
- Sub-nav aparece solo cuando se activa workspace Viajes

**Tab Inicio — dashboard con 6 tarjetas KPI clickeables**:
- 📋 Pedidos nuevos para revisar (naranja urgente si >0)
- 📦 Listos para consolidar
- ✏️ Borradores sin publicar
- 🤝 Sin proveedor por adjudicar
- 🚛 En ruta rodando
- 📬 Entregados pendiente cerrar
- + footer stats (total pedidos, total viajes, flete total)
- Click card → salta al tab + filtros pre-aplicados
- Saludo dinámico por hora ("Buenos días, Bernardo 👋")

**Tab Pedidos — unificado con full admin**:
- Filtros: pills multiselect de estado (Nuevos / Sin consolidar / Consolidado / Asignado / Entregado / Cancelado / Rechazado), ref, cliente, origen, destino, zona, rango de fechas (7d/30d/90d presets).
- Filtros especiales (bypass estado): `🔗 Sin viaje` (solo pedidos con viaje_id=NULL), `⚠ Inconsistentes` (estado terminal sin viaje — data quality issues).
- Badges: NUEVO (naranja) si revisado_at IS NULL, estado canónico si revisado, `⚠ sin viaje` si inconsistente.
- Agrupado visual por origen con select-all por grupo.
- Bulk actions: `↶ Nuevos` (revertir revisión), `↺ Resetear` (→ sin_consolidar + viaje_id=NULL), `⇄ Cambiar estado` (forzar cualquier estado con razón), `✕ Cancelar` (→ cancelado), `🗑 Eliminar` (DELETE hard con snapshot en audit), `Consolidar →` (crea viaje).
- Por fila: ℹ detalle completo, ✎ editar (28 campos), ⎘ clonar para reintento en nuevo viaje.

**Tabs Asignar proveedor / En seguimiento / Historial** (viajes):
- Tab Asignar proveedor: viajes pendiente (fuente=netfleet o publicados). Toggle "Incluir migrados Sheet". Modales consolidar (Ridge sugerido + publicar inline), ajustar_precio, asignar_directo.
- Tab En seguimiento: viajes confirmado/en_ruta/entregado. Filtros por proveedor + fecha cargue. Checkboxes + action bar para **cerrar bulk** con razón (pasa a finalizado). Botón `↩ Reabrir adjudicación` por card confirmado.
- Tab Historial: viajes finalizado/cancelado. Botón `↩ Deshacer cierre` en finalizados.
- Cada viaje card expandida muestra: proveedor (FK o texto legacy), fecha/zona/valor, embalaje total (contenedores/cajas/bidones/canecas/unidades), vehículo + placa + conductor + km, observaciones, stats ($/kg, $/km, $/pedido, %flete-vs-valor), pedidos incluidos (colapsables con detalle completo), tags 🏆 subasta / 📌 directa.

**Auto-switch** de tab tras cada acción. Toasts descriptivos con proveedor/destino ("Asignado directo a VIGÍA → ver en Seguimiento").

### Supabase — estado al 2026-04-22

| Tabla | Rows | Notas |
|---|---|---|
| `clientes` | 2 | AVGUST + FATECO (ambos `plan_bpo=true`) |
| `transportadoras` | 7 | Seed: ENTRAPETROL, TRASAMER, JR, Trans Nueva Colombia, PRACARGO, Global, Vigía |
| `perfiles` | 3 | 1 `logxie_staff` (Bernardo) + 2 `transportador` pendientes |
| `viajes_consolidados` | **1297+** | Sincronizados con Sheet ASIGNADOS. Fuente `sheet_asignados` mayoría + nuevos `netfleet` tras promociones de scenarios |
| `pedidos` | **3748+** | ~97% linkeados. Linker v3 (regex) + v4 (substring BUSCARX-style) en cascada |
| `scenarios_viaje` | ✨ nueva | Capa tentativa de consolidación. Estados: borrador / promovido / descartado / conflictivo / invalidado. 2026-04-22 |
| `scenarios_viaje_pedidos` | ✨ nueva | N:M pedidos↔scenarios con orden de ruta |
| `ofertas` | 0 | Aún sin ofertas reales (falta Apps Script mail→Netfleet + onboarding transportadoras) |
| `invitaciones_subasta` | 0 | Ninguna todavía |
| `acciones_operador` | 40+ | Audit trail M4 + sync + admin pedidos + scenarios |

### Supabase — Postgres functions listas

**Módulo 4 ciclo de operación** — 12 functions `SECURITY DEFINER`:

| Function | Propósito |
|---|---|
| `fn_consolidar_pedidos(ids[], metadata)` | Crea viaje desde N pedidos |
| `fn_agregar_pedido_a_viaje` | Añade pedido a viaje pendiente |
| `fn_quitar_pedido_de_viaje` | Saca pedido (auto-cancela viaje si vacío) |
| `fn_desconsolidar_viaje` | Cancela viaje + libera pedidos |
| `fn_ajustar_precio_viaje` | Cambia flete (solo antes de confirmar) |
| `fn_publicar_viaje` | Abre subasta (abierta/cerrada) |
| `fn_invitar_transportadora` | Invita a subasta cerrada |
| `fn_asignar_transportadora_directo` | Skippea subasta, adjudica directo |
| `fn_adjudicar_oferta` | Gana oferta → viaje confirmado |
| `fn_reabrir_viaje` | `confirmado → pendiente` (libera proveedor) |
| `fn_cerrar_viaje` + `fn_cerrar_viajes_batch` | `confirmado → finalizado`, pedidos → entregado |
| `fn_reabrir_finalizado` | Deshace cierre: `finalizado → confirmado` |

**Sync Sheets→Netfleet** — 2 functions:
- `fn_sync_viajes_batch(jsonb)` — UPSERT batch desde ASIGNADOS
- `fn_sync_pedidos_batch(jsonb)` — UPSERT batch desde Base_inicio-def

**Admin pedidos** (creadas 2026-04-20) — 5 functions:
- `fn_marcar_revisado(id, notas)` — de Nuevos → Sin consolidar
- `fn_marcar_no_revisado(id, razon)` — revertir a Nuevos
- `fn_pedidos_cancelar_batch(ids[], razon)` — bulk → cancelado
- `fn_pedidos_resetear_batch(ids[], razon, marcar_nuevo)` — bulk → sin_consolidar
- `fn_pedido_clonar(id, razon)` — duplica row para reintento
- `fn_pedido_editar(id, campos_jsonb)` — update 29 campos con audit
- `fn_pedidos_cambiar_estado_batch(ids[], nuevo_estado, razon)` — forzar estado
- `fn_pedidos_eliminar_batch(ids[], razon)` — DELETE hard con snapshot

**Scenarios — capa tentativa** (creadas 2026-04-22) — 6 functions:
- `fn_scenario_crear(pedido_ids[], nombre?, notas?)` — crea scenario sin cambiar estado de pedidos; nombre autogenerado si no se pasa
- `fn_scenario_agregar_pedido(scenario_id, pedido_id)` — suma pedido (solo borrador/conflictivo)
- `fn_scenario_quitar_pedido(scenario_id, pedido_id)` — saca pedido
- `fn_scenario_descartar(id, razon?)` — marca descartado
- `fn_scenario_limpiar_consumidos(id)` — quita pedidos que ya se consumieron en otro scenario; vuelve a borrador si quedan libres, invalidado si no
- `fn_scenario_promover(id, metadata)` — delega a `fn_consolidar_pedidos`, crea viaje, marca otros scenarios conflictivos/invalidados automáticamente

**Helpers**:
- `is_logxie_staff()` — SECURITY DEFINER, checkea `perfiles.tipo='logxie_staff'` via `auth.uid()`
- `_recalc_viaje_agregados(viaje_id)` — recomputa peso/valor/cantidad
- `_recalc_scenario(scenario_id)` — recomputa agregados + zonas
- `_norm_empresa(text)` — canoniza "FATECO, AVGUST" → "AVGUST, FATECO"
- `_norm_estado_viaje` / `_norm_estado_pedido` — estados crudos → canónicos

### Script Python para backfill + ETL manual

[db/sync_from_csv.py](../db/sync_from_csv.py) — CLI que lee CSV export de Sheets y llama las RPC en batches de 500:
- Encoding fallback: UTF-8 → cp1252 → latin-1 (Excel Windows ES)
- Delimiter auto-detect (, vs ;)
- Flag `--truncate` para migración limpia
- Auto-corre `post_migration.sql` + `link_pedidos_viajes_v3.sql`
- Uso: `python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv [--truncate]`

### Linker v3 + v4 — cascada 2026-04-20

**Pase 1 — v3 (regex estructurado)** — [db/link_pedidos_viajes_v3.sql](../db/link_pedidos_viajes_v3.sql):
- **Regla confirmada por operador**: separador entre pedidos = `,`. Los `-` y `/` dentro de un token son ALIASES del mismo pedido, NO rangos.
- Split por `,` → cada token = 1 pedido lógico. Dentro del token, regex global extrae todos los (prefijo, número). Los sin prefijo heredan el último prefijo visto.
- Ejemplos corregidos:
  - `RM-72781-72803` → [RM-72781, RM-72803] (aliases, NO rango de 23)
  - `RM-72782/72783/72784` → [RM-72782, RM-72783, RM-72784]
  - `TI-54710 - TIT-2188` → [TI-54710, TIT-2188]
  - `DEVOLUCION, RM-72777` → [RM-72777]
- Maneja también espacios alrededor de dashes: `"TI -00001968"` → `TI-1968` (fix 2026-04-20 tarde)
- Resultado: no hay más sobrelinkeos por rangos imposibles (ej. `RM-70325 - 73028` ya no genera 2704 refs fantasma).

**Pase 2 — v4 (substring BUSCARX-style)** — [db/link_pedidos_viajes_v4.sql](../db/link_pedidos_viajes_v4.sql):
- Replica fórmula de Bernardo en Google Sheets: `=BUSCARX("*"&ref&"*"; PEDIDOS_INCLUIDOS; ID_CONSOLIDADO)`
- SQL: `PEDIDOS_INCLUIDOS ILIKE '%' || pedido_ref || '%'`
- Rescata huérfanos que el regex v3 no encontró (refs con formato extraño, embebidos en texto narrativo)
- Guardrails:
  - Solo refs con length ≥5 (evita "RM-6" matcheando "RM-60", "RM-600")
  - Solo matches ÚNICOS (si >1 viaje candidato, skip — ambiguo)
  - Preferencia: cliente_id match > NULL
- Resultado combinado: 91.7% → **97.3% linked** (+211 rescatados)

### n8n (automatización actual)
- Workflow procesando correos de Avgust/Fateco → parsea viajes → Ridge v2 → Sheet
- Webhook de `checkderuta.html` recibiendo check-ins
- **PENDIENTE**: workflow cron 15min que llame a `fn_sync_viajes_batch` / `fn_sync_pedidos_batch` con datos del Sheet via Google Sheets API (credencial `IuCNLIa09oW4ZWBu`)

### Datos
- **Google Sheet** ID `1rqCdVATX9cWQJ3zL2s5PO82EE_KmXTqIeg_oj7DAHE4` sigue siendo fuente principal — AppSheet escribe, n8n parsea, sync actualiza Netfleet
- **Pestañas ASIGNADOS + Base_inicio-def** son fuente autoritativa del sync hasta que se abandone AppSheet
- **Modelo Ridge** R²=0.919, entrenado con 1,015 viajes reales

---

## Qué está pendiente

### 🚀 Propuesta activa — Rediseño Lean/Kanban de control.html (decisión Bernardo 2026-04-20)

Bernardo expresó confusión con tabs actuales ("Pedidos, Asignar proveedor, En seguimiento, Historial" mezcla unidades). Propuse y confirmó reestructuración:

**Workspaces orientados al customer journey del día operativo**:
1. **🏠 Inicio**: dashboard con tarjetas KPI clickeables (12 pedidos para revisar → Revisar / 3 viajes sin proveedor → Asignar / 5 camiones en ruta → Seguir).
2. **📥 Pedidos** (kanban 3 cols): `Para revisar | Listos para consolidar | En viaje (archivo)`. Selección múltiple en Listos → Consolidar → aparece en Viajes.
3. **🚚 Viajes** (kanban 5 cols): `Borrador | En subasta | Confirmado | En ruta | Entregado`. Cada card con acciones contextuales por columna.
4. **📚 Archivo** (tabla lateral): finalizados + cancelados, read-mostly.

Pendiente decidir: columnas nombradas con verbos (`Revisar | Consolidar | Publicar | Adjudicar | Seguir | Entregar | Cerrar`) vs sustantivos-estado. Mi recomendación: verbos (más accionables Lean).

Principios Lean aplicados: make work visible, pull-not-push, 1-click per action, flow focus, contextual CTAs, undo-friendly.

**Estimación**: Fase 1 (Kanban MVP) ~1-2h. Fase 2 (drag&drop, atajos teclado, undo toasts) separada.

### Módulo 4 — Siguiente paso (sync automático)

- [ ] **Workflow n8n cron 15min** — lee Google Sheets (ASIGNADOS + Base_inicio-def) → normaliza → POST a `/rest/v1/rpc/fn_sync_viajes_batch` y `fn_sync_pedidos_batch` con bearer service_role. Opcional: webhook HTTP separado para disparo manual desde control.html.
- [ ] **Botón 🔄 Sync en control.html** — POST al webhook n8n para sincronización on-demand.
- [ ] **Integración email** — decidir: n8n webhook vs Supabase Edge Function (Resend/SendGrid). Para `fn_publicar_viaje` + `fn_invitar_transportadora` + `fn_adjudicar_oferta`.
- [ ] **Deep-linking `transportador.html`**: query param `?viaje_ref=...` → scroll + highlight del viaje.
- [ ] **RLS endurecer en `viajes_consolidados`**: hoy `authenticated_all` permisivo. Cambiar a `subasta_tipo='abierta' OR existe invitación`.
- [ ] **Data quality**: revisar los 434 huérfanos. Muchos son refs typeados mal en el Sheet (RM-70xxx cuando era RM-72xxx), rangos imposibles cross-prefix, o DEVOLUCION-style placeholders.

### Módulo 3 — Tracking (diferido)

- [ ] Schema separado `tracking.*`:
  - `tracking.entregas` (N intentos por pedido, timestamps, fotos, novedad, comentario, geoloc)
  - `tracking.eventos_viaje` (cargue_llegada/salida, descargue_llegada/salida)
  - `tracking.checkins` (pings de ubicación)
- [ ] ALTER `pedidos`: agregar `entregado_at`, `novedad_actual`, `foto_cumplido_url`
- [ ] ALTER `viajes_consolidados`: agregar `cargue_llegada`, `cargue_salida`, `descargue_llegada`, `descargue_salida`, `conductor_email`, `conductor_whatsapp`
- [ ] `conductor.html` mobile-first — reemplaza AppSheet "NAVEGADOR"
- [ ] Decisión auth conductores: cuenta propia vs magic link WhatsApp vs QR por viaje
- [ ] PWA con sync offline

### Módulo 2 — Ingesta automática (parcial)

- [x] ✅ Schema + backfill (clientes, viajes_consolidados, pedidos) — 2026-04-17
- [x] ✅ Linker v3 con aliases correctos — 2026-04-20 (88.4% linked, más correcto que v2 94.7%)
- [x] ✅ Sync Sheets→Supabase funcional vía fn_sync_*_batch + sync_from_csv.py
- [ ] **Parser 2 real — Pull Sheets de clientes externos** (cuando haya otros BPO)
- [ ] **Parser 3 — Webhook HTTP** (Nivel 4 — CRM Avgust futuro)
- [ ] **Parser 1 — Email texto libre** (Nivel 1) — Gmail + Claude API extrae campos

### Módulo 1 — Subasta (cerrar gaps)

- [x] ✅ Tabla `ofertas` creada
- [ ] Crear tablas `leads` y `cargas` (documentadas pero no existen)
- [ ] Countdown y notificación de adjudicación en `transportador.html`
- [ ] Fix formato `ofertas.viaje_id` — la tabla nueva usa UUID FK; el frontend legacy hitea por `viaje_rt` TEXT

### Admin panel (diferido a nueva sesión — Bernardo solicitó)

Ampliar `control.html` como hub único de admin Logxie:
- **Clientes** — CRUD tabla `clientes` (hoy AVGUST + FATECO, mañana nuevos BPO)
- **Transportadoras** — CRUD tabla `transportadoras`
- **Usuarios** — CRUD `perfiles` (reemplaza `admin.html`)

Deferidos dentro de Admin:
- **Conductores** — necesita tabla `conductores` nueva. Parte natural de M3.
- **Crear usuarios staff desde UI** — hoy requiere Dashboard. Solución: Edge Function con service_role key.

### Seguridad — 🔥 urgente

- [ ] **Rotar password de Supabase DB** — `Bjar1978*ABC` quedó en texto plano en sesiones
- [ ] **Rotar Anthropic API key** — quedó en `LogxIA/CLAVES Y APIS.txt` antes de gitignore
- [ ] **Rotar Telegram bot token** — `@BotFather` → `/revoke`

### Ingeniería — deuda técnica

- [ ] **5 copias de CIUDADES/estimarPrecio en HTML** — centralizar en `netfleet-core.js`
- [ ] **Bug 2-opt en index.html línea ~1483**: fallback de `pts[j+1]` cuando j es último índice
- [ ] **`viaje.html`**: sort por latitud en vez de nearest-neighbor/2-opt
- [ ] **Banner "modo demo"** cuando CSV falla y se muestran 2 viajes hardcoded
- [ ] **Rangos históricos del estimador** son estáticos — update periódico

### Operación

- [ ] **Plan de contingencia Publish-to-Web del Sheet** — si se rompe, fallback silencioso a 2 viajes
- [ ] **Precios viejos del Sheet** calculados con n8n v1 (lineal). Solo nuevos usan Ridge v2

---

## Próximos pasos inmediatos (para abrir sesión siguiente)

### 🔄 Botón Sync on-demand (MVP, ~30 min)

Bernardo solicitó "ver en tiempo real lo de Google Sheets en Supabase o al menos lo de los 15 minutos".

**Requisito de Bernardo antes de seguir**: publicar los 2 Sheets como CSV públicos (pestañas ASIGNADOS + Base_inicio-def) y pasar las URLs.
- Google Sheets → Archivo → Compartir → Publicar en la Web → pestaña + CSV → Publicar
- Copiar URL generada

**Luego implemento**:
1. `fn_run_linkers()` SQL — wrapper que corre v3 + v4 en secuencia
2. Botón **🔄 Sync** en header de control.html
3. JS: fetchea los 2 CSVs públicos → parsea con PapaParse → mapea columnas a JSON canónico → llama `fn_sync_viajes_batch` + `fn_sync_pedidos_batch` + `fn_run_linkers()` → toast con counters
4. Resultado: 1 click = sync completo en ~5 seg, on-demand

### 🔄 Cron 15min automático (siguiente, después del botón)

Usa el mismo backend. 2 caminos:
- **n8n**: workflow Schedule 15min → HTTP POST a RPCs. Armar JSON para importar.
- **GitHub Actions**: workflow en repo con `schedule: '*/15 * * * *'` que corre el mismo flow. Zero infra nueva.

### 🧹 Sanitizar pedido_ref al guardar (15 min)

Helper `_norm_pedido_ref(text)` (trim + strip whitespace around `-` + upper case). Aplicar en `fn_sync_pedidos_batch` INSERT/UPDATE/lookup. Previene duplicados cuando el Sheet se corrige (ej. "TI -00001968" → "TI-00001968" tras corrección). + UPDATE masivo para normalizar los ~100 pedidos ya cargados con formato feo.

### 📧 Email notificaciones (JTBD Viajes — 1-2h)

Al adjudicar/asignar/cerrar viaje: disparar emails a:
- Proveedor (transportadora ganadora)
- Usuario solicitante (equipo Avgust)
- Facturación (c.vahos@avgust.com.co)
- Bodega (bodega_email del pedido)

Opciones provider: Resend, SendGrid, Gmail API con OAuth. Decidir.
Botón **📧 Notificar** en card de viaje + templates HTML (similar al mail actual del Apps Script).

### 🎨 Kanban Fase 2 (futuro)

Columnas horizontales lado-a-lado + drag&drop entre estados. Refactor mayor — fuera de MVP actual.

### Otros pendientes (menos priorizados)

- **RLS endurecer en `viajes_consolidados`**: hoy `authenticated_all` permisivo
- **Deep-linking `transportador.html`**: query param `?viaje_ref=...`
- **Admin tab clientes/transportadoras/usuarios** en control.html (reemplaza admin.html)
- **Data quality cleanup** de los 101 huérfanos — mayoría son data issues del Sheet (placeholders, typos del operador, refs nunca consolidados)
- **Rotar password Supabase** — urgente pero no bloqueante

---

## Notas operativas

### DATABASE_URL correcto (PowerShell)
```powershell
$env:DATABASE_URL="postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
```

### Correr SQL en Supabase
```powershell
python db/run_migration.py --file db/<archivo>.sql
```

### Correr sync desde CSV (manual)
```powershell
python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv [--truncate]
```

**Importante**: exportar los CSV DIRECTAMENTE desde Google Sheets (Archivo → Descargar → CSV). No abrir con Excel antes — Excel corrompe el formato (agrega `;;;;;` trailing, usa `;` como delimitador, rompe multi-line observaciones). El script auto-detecta delimitador y encoding pero funciona mejor con CSVs de Google Sheets puros.

### Sensibilidades del sistema

- **Supabase anon key**: usar JWT largo (`iat:1775536019`). NUNCA `sb_publishable_`.
- **`estado: 'aprobado'`** (no `'activo'`) en `perfiles`. Frontend depende del string exacto.
- **Password DB**: comprometida. Rotar.
- **Gate de sync/admin functions**: acepta `is_logxie_staff()` OR `service_role` OR `session_user IN ('postgres','supabase_admin')`.
- **Paginación en control.html**: cada fetch de `pedidos`/`viajes_consolidados` usa `getJsonPaginated` con `order=...,id.desc` (secondary sort estable — sin este fix, rows con mismo `created_at` duplicaban entre páginas porque todo el sync inicial ejecutó en el mismo segundo).

### Deploy
- Push a `main` → Cloudflare Pages auto-deploy 1-2min.
- No hay staging. Probar local antes (`static-server` en puerto 8080).
- `_headers` fuerza `Cache-Control: no-cache`.

### Contacto responsable
- **Bernardo Aristizabal** — bernardoaristizabal@logxie.com — +573214401975
- **Logxie Connect S.A.S.**

### Enlaces clave
- Producción: https://netfleet.app
- Repo: https://github.com/Logxie-Projects/cargachat (branch `main`)
- Supabase: https://pzouapqnvllaaqnmnlbs.supabase.co
- Admin legacy: https://netfleet.app/admin.html
- Control staff: https://netfleet.app/control.html
- Último commit: `e4d8c38` — "feat(analizador): migración a Supabase + selector dual viaje/scenario"

---

*Última actualización: 2026-04-22 (sesión journey + scenarios + analizador Supabase)*
