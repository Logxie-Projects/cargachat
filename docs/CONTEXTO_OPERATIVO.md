# Estado actual Netfleet

> Foto del proyecto al **2026-04-19** (sesión de sync Sheets↔Netfleet). Este documento se actualiza conforme se avanza — leer primero para tener contexto de qué está vivo, qué falta, y dónde están los riesgos hoy.

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
- **Control staff** (`control.html`) — Módulo 4 UI en producción y en uso por Bernardo. 4 tabs (Sin consolidar / Consolidados / Activos / Historial), consolidar con Ridge sugerido + publicar inline, adjudicar, asignar directo, reabrir viajes confirmados, desconsolidar, detalle completo de pedidos (embalaje/contacto/dirección/horario/observaciones), stats por viaje ($/kg, $/km, $/pedido, %flete-vs-valor), tags de adjudicación (🏆 subasta / 📌 directa), badges de estado (borrador/abierta/cerrada), auto-switch de tab tras cada acción, toggle "incluir migrados Sheet ASIGNADOS", agrupar sin_consolidar por origen, filtro de fechas 7d/30d/90d.

### Supabase — estado al 2026-04-19

| Tabla | Rows | Notas |
|---|---|---|
| `clientes` | 2 | AVGUST + FATECO (ambos `plan_bpo=true`) |
| `transportadoras` | 7 | Seed: ENTRAPETROL, TRASAMER, JR, Trans Nueva Colombia, PRACARGO, Global, Vigía |
| `perfiles` | 3 | 1 `logxie_staff` (Bernardo) + 2 `transportador` pendientes |
| `viajes_consolidados` | **1281** | **100% sincronizados con Sheet ASIGNADOS**. Todos `fuente='sheet_asignados'`. 0 netfleet (truncate fresh 2026-04-19) |
| `pedidos` | **3740** | 94.7% linkeados (3543 con viaje_id, 197 huérfanos) |
| `ofertas` | 0 | Ninguna todavía |
| `invitaciones_subasta` | 0 | Ninguna todavía |
| `acciones_operador` | 25+ | Audit trail M4 + sync |

### Supabase — Postgres functions listas

**Módulo 4 ciclo de operación** (9 functions `SECURITY DEFINER` con gate `is_logxie_staff()`):

- `fn_consolidar_pedidos(ids[], metadata)` — crea viaje desde N pedidos
- `fn_agregar_pedido_a_viaje(viaje, pedido)` — añade uno
- `fn_quitar_pedido_de_viaje(pedido)` — saca uno (auto-cancela si queda vacío)
- `fn_desconsolidar_viaje(viaje)` — deshace todo
- `fn_ajustar_precio_viaje(viaje, nuevo, razon)` — ajuste antes de publicar
- `fn_publicar_viaje(viaje, tipo)` — abre subasta (`abierta`/`cerrada`)
- `fn_invitar_transportadora(viaje, transp)` — invita a subasta cerrada
- `fn_asignar_transportadora_directo(viaje, transp, precio, razon)` — skippea subasta
- `fn_adjudicar_oferta(oferta)` — gana oferta → viaje confirmado
- `fn_reabrir_viaje(viaje_id, razon)` — revierte `confirmado → pendiente` (proveedor y adjudicación liberados, ofertas reactivadas si era subasta)

**Sync Sheets→Netfleet** (creadas 2026-04-19):
- `fn_sync_viajes_batch(jsonb)` — UPSERT batch desde ASIGNADOS. Regla: Netfleet gana (fuente=netfleet skip), terminales skip, cancelado propaga.
- `fn_sync_pedidos_batch(jsonb)` — UPSERT batch desde Base_inicio-def. Regla: match por `(cliente_id, pedido_ref)` no-terminal más reciente. Cancelado propaga.
- Ambas con audit en `acciones_operador` (accion='sync_viajes'/'sync_pedidos').

**Helpers**:
- `is_logxie_staff()` — SECURITY DEFINER, checkea `perfiles.tipo='logxie_staff'` via `auth.uid()`
- `_recalc_viaje_agregados(viaje_id)` — recomputa peso/valor/cantidad de un viaje desde sus pedidos
- `_norm_empresa(text)` — canoniza variantes ("FATECO, AVGUST" → "AVGUST, FATECO"). Usado en fn_sync_*.
- `_norm_estado_viaje(text)` / `_norm_estado_pedido(text)` — mapea estados crudos del Sheet a canónicos

### Script Python para backfill y ETL manual

- [db/sync_from_csv.py](../db/sync_from_csv.py) — CLI que lee CSV export de Sheets y llama las RPC en batches de 500. Soporta `--truncate` para migración limpia. Auto-corre `post_migration.sql` + `link_pedidos_viajes_v2.sql`.
- Uso: `python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv [--truncate]`

### n8n (automatización)
- Workflow procesando correos de Avgust/Fateco → parsea viajes → Ridge v2 → Sheet
- Webhook de `checkderuta.html` recibiendo check-ins
- **PENDIENTE**: workflow cron 15min que llame a `fn_sync_viajes_batch` / `fn_sync_pedidos_batch` con datos del Sheet via Google Sheets API (credencial `IuCNLIa09oW4ZWBu`)

### Datos
- **Google Sheet** gid=1690776181 sigue siendo la fuente principal — AppSheet escribe, n8n parsea, frontend lee CSV público
- **Google Sheet ASIGNADOS + Base_inicio-def** ahora son también **fuente autoritativa del sync a Netfleet** (hasta que se abandone AppSheet)
- **Modelo Ridge** R²=0.919, entrenado con 1,015 viajes reales

---

## Qué está pendiente

### Módulo 4 — Siguiente paso (sync automático)

- [ ] **Workflow n8n cron 15min** — lee Google Sheets (ASIGNADOS + Base_inicio-def) → normaliza → POST a `/rest/v1/rpc/fn_sync_viajes_batch` y `fn_sync_pedidos_batch` con bearer service_role. Opcional: webhook HTTP separado para disparo manual desde control.html.
- [ ] **Botón 🔄 Sync en control.html** — POST al webhook n8n para sincronización on-demand. Header nav, toast con counters.
- [ ] **Integración email** — decidir: n8n webhook vs Supabase Edge Function (Resend/SendGrid). Para `fn_publicar_viaje` + `fn_invitar_transportadora` + `fn_adjudicar_oferta`. Al publicar viaje, mandar mail a proveedores con link a `transportador.html?viaje_ref=NF-...`.
- [ ] **Deep-linking `transportador.html`**: query param `?viaje_ref=...` → scroll + highlight del viaje.
- [ ] **RLS endurecer en `viajes_consolidados`**: hoy `authenticated_all` permisivo. Cambiar a `subasta_tipo='abierta' OR existe invitación`.
- [ ] **Data quality**: revisar los 197 pedidos huérfanos + 128 viajes vacíos (sin pedidos linkeados). Probablemente son refs que no matchean por formato — investigar en futura sesión.

### Módulo 3 — Tracking (diferido)

- [ ] Schema separado `tracking.*`:
  - `tracking.entregas` (N intentos por pedido, timestamps, fotos, novedad, comentario, geoloc)
  - `tracking.eventos_viaje` (cargue_llegada/salida, descargue_llegada/salida)
  - `tracking.checkins` (pings de ubicación)
- [ ] ALTER `pedidos`: agregar `entregado_at`, `novedad_actual`, `foto_cumplido_url` (shortcuts cacheados del último intento).
- [ ] ALTER `viajes_consolidados`: agregar `cargue_llegada`, `cargue_salida`, `descargue_llegada`, `descargue_salida`, `conductor_email`, `conductor_whatsapp`.
- [ ] `conductor.html` mobile-first — reemplaza AppSheet "NAVEGADOR".
- [ ] Decisión auth conductores: cuenta propia vs magic link WhatsApp vs QR por viaje.
- [ ] PWA con sync offline (camiones en zonas muertas).

### Módulo 2 — Ingesta automática (parcial)

- [x] ✅ Schema migrado (clientes, viajes_consolidados, pedidos) — 2026-04-17
- [x] ✅ Linker pedidos→viajes v2 con PEDIDOS_INCLUIDOS + canonicalización — 2026-04-17 (92% match, 94.7% después del sync fresh 2026-04-19)
- [x] ✅ **Sync unidireccional Sheets→Supabase** vía funciones Postgres + script Python — 2026-04-19 (backfill ejecutado, cubre Parser 4 + parte de Parser 2)
- [ ] **Parser 2 real — Pull Sheets de clientes externos** (Nivel 2 ingesta) — cuando haya otros clientes BPO además de AVGUST/FATECO
- [ ] **Parser 3 — Webhook HTTP** (Nivel 4 ingesta — CRM Avgust futuro)
- [ ] **Parser 1 — Email texto libre** (Nivel 1) — Gmail + Claude API extrae campos

### Módulo 1 — Subasta (cerrar gaps)

- [x] ✅ Tabla `ofertas` creada — 2026-04-17
- [ ] Crear tablas `leads` y `cargas` (documentadas en CLAUDE.md pero no existen)
- [ ] Countdown y notificación de adjudicación en `transportador.html`
- [ ] Fix formato `ofertas.viaje_id` — la tabla nueva usa UUID FK; el frontend legacy hitea por `viaje_rt` TEXT. Migrar frontend cuando se toque M1

### Admin (diferido a próxima sesión — Bernardo solicitó)

Ampliar `control.html` como hub único de admin Logxie. Nueva tab **"Admin"** con 3 sub-secciones:
- **Clientes** — listar/crear/editar tabla `clientes` (hoy AVGUST + FATECO, mañana nuevos BPO)
- **Transportadoras** — listar/crear/editar tabla `transportadoras`
- **Usuarios** — listar/aprobar/rechazar/cambiar tipo de `perfiles` (reemplaza `admin.html`)

Estimación: 2-3h. Prerequisito para crear usuarios staff/conductores en vivo sin tocar SQL Editor.

Deferidos dentro de Admin:
- **Conductores** — necesita crear tabla `conductores` nueva. Parte natural de Módulo 3.
- **Crear usuarios staff desde UI** — hoy requiere Dashboard (anon key no puede crear auth.users). Solución: Edge Function con service_role que wrappee `auth.admin.createUser`.

### Seguridad — 🔥 urgente

- [ ] **Rotar password de Supabase DB** — `Bjar1978*ABC` quedó en texto plano en sesiones de chat. Dashboard → Project Settings → Database → Reset password.
- [ ] **Rotar Anthropic API key** — quedó en texto plano en `LogxIA/CLAVES Y APIS.txt` antes de gitignorarla.
- [ ] **Rotar Telegram bot token** — en `@BotFather` → `/revoke` → `/token`.

### Ingeniería — deuda técnica

- [ ] **5 copias de CIUDADES/estimarPrecio en HTML** — centralizar en `netfleet-core.js`. Ver CLAUDE.md "Decisiones Técnicas Tomadas".
- [ ] **Bug 2-opt en index.html línea ~1483**: fallback de `pts[j+1]` cuando j es último índice.
- [ ] **`viaje.html`**: sort por latitud en vez de nearest-neighbor/2-opt.
- [ ] **Banner "modo demo"** cuando CSV falla y se muestran 2 viajes hardcoded.
- [ ] **Rangos históricos del estimador** son estáticos — update periódico con data nueva.

### Operación

- [ ] **Plan de contingencia Publish-to-Web del Sheet** — si se rompe, fallback a 2 viajes hardcoded sin alerta visible.
- [ ] **Precios viejos del Sheet** calculados con n8n v1 (lineal). Solo nuevos usan Ridge v2.

---

## Próximos pasos inmediatos

1. **Armar workflow n8n cron 15min + webhook** — para sync automático AppSheet→Netfleet. Ya existen las funciones Postgres, falta el trigger. Sin esto, Bernardo debe correr manualmente el script Python periódicamente.
2. **Botón 🔄 Sync en control.html** — UI para disparar el webhook. Complemento del cron.
3. **Bernardo empieza a consolidar viajes reales en control.html** — ya puede, la BD está limpia y sincronizada.
4. **Data quality**: investigar los 197 pedidos huérfanos + 128 viajes vacíos (si son data real o artefactos del Sheet).
5. **Rotar password Supabase** — no bloqueante pero urgente.
6. **Admin tab en control.html** — ampliar para crear/editar clientes/transportadoras/usuarios.

---

## Notas operativas

### DATABASE_URL correcto (PowerShell)
```powershell
$env:DATABASE_URL="postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
```
- Región: `aws-1-us-east-1` (NO `aws-0-`)
- User: `postgres.pzouapqnvllaaqnmnlbs` (CON el punto)
- `*` en password = `%2A` URL-encoded
- Direct connection (`db.XXX.supabase.co`) NO funciona — solo pooler

### Correr SQL en Supabase
```powershell
python db/run_migration.py --file db/<archivo>.sql
```
- Idempotente: todos los `.sql` de M4 son safe para re-run
- Output: solo imprime resultados del último statement
- Para ver resultado de una query en medio, hacerla la última

### Correr sync desde CSV
```powershell
# Export ASIGNADOS y Base_inicio-def como CSV desde Google Sheets
# Guardar en D:\NETFLEET\dumps\

python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv

# Con --truncate para migración limpia (destruye viajes+pedidos primero)
python db/sync_from_csv.py --viajes dumps/asignados.csv --pedidos dumps/base_inicio_def.csv --truncate
```
- Script parsea CSVs ANTES de truncar (si falla parse, no daña BD)
- Pide confirmación antes de TRUNCATE (escribir "si")
- Corre post_migration.sql + link_pedidos_viajes_v2.sql automáticamente al final
- Ignora headers del Sheet sin mapeo con warning (útil para debug)

### Sensibilidades del sistema

- **Supabase anon key**: usar JWT largo (`iat:1775536019`). NUNCA `sb_publishable_`.
- **`estado: 'aprobado'`** (no `'activo'`) en `perfiles`. Frontend depende del string exacto.
- **Password DB**: comprometida. Rotar.
- **Gate de sync functions**: acepta `is_logxie_staff()` OR `current_setting('role')='service_role'` OR `session_user IN ('postgres','supabase_admin')`. El script Python corre como postgres superuser via pooler.

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
- Control staff: https://netfleet.app/control.html (login con bernardoaristizabal@logxie.com)
- Último commit: `920b457` — "feat: normalizador de empresa en fn_sync_*_batch"

---

*Última actualización: 2026-04-19*
