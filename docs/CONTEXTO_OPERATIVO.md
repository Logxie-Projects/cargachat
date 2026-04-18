# Estado actual Netfleet

> Foto del proyecto al **2026-04-17** (tarde/noche). Este documento se actualiza conforme se avanza — leer primero para tener contexto de qué está vivo, qué falta, y dónde están los riesgos hoy.

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

### Supabase — tablas vivas (al 2026-04-17)

| Tabla | Rows | Propósito |
|---|---|---|
| `clientes` | 2 | AVGUST, FATECO (ambos `plan_bpo=true`) |
| `perfiles` | 0 | **Recién creada en esta sesión** — antes no existía |
| `viajes_consolidados` | 1281 | Migrados desde Sheet ASIGNADOS |
| `pedidos` | 3764 | Migrados desde Sheet Base_inicio-def (92% linkeados a viajes) |
| `transportadoras` | 7 | Seed: ENTRAPETROL, TRASAMER, JR, Trans Nueva Colombia, PRACARGO, Global, Vigía |
| `ofertas` | 0 | **Recién creada** — ciclo de subasta |
| `invitaciones_subasta` | 0 | **Recién creada** — subastas cerradas (invite-only) |
| `acciones_operador` | 0 | **Recién creada** — audit trail M4 |

### Supabase — 9 Postgres functions listas (Módulo 4)
Todas `SECURITY DEFINER` con gate `is_logxie_staff()`:

- `fn_consolidar_pedidos(ids[], metadata)` — crea viaje desde N pedidos
- `fn_agregar_pedido_a_viaje(viaje, pedido)` — añade uno
- `fn_quitar_pedido_de_viaje(pedido)` — saca uno (auto-cancela si queda vacío)
- `fn_desconsolidar_viaje(viaje)` — deshace todo
- `fn_ajustar_precio_viaje(viaje, nuevo, razon)` — ajuste antes de publicar
- `fn_publicar_viaje(viaje, tipo)` — abre subasta (`abierta`/`cerrada`)
- `fn_invitar_transportadora(viaje, transp)` — invita a subasta cerrada
- `fn_asignar_transportadora_directo(viaje, transp, precio, razon)` — skippea subasta
- `fn_adjudicar_oferta(oferta)` — gana oferta → viaje confirmado

Más helper `_recalc_viaje_agregados(viaje_id)` (uso interno, recomputa peso/valor/cantidad).

### n8n (automatización)
- Workflow procesando correos de Avgust/Fateco → parsea viajes → Ridge v2 → Sheet
- Webhook de `checkderuta.html` recibiendo check-ins

### Datos
- **Google Sheet** gid=1690776181 sigue siendo la fuente principal de viajes (escribe n8n al Sheet y frontend lee CSV público).
- **Modelo Ridge** R²=0.919, entrenado con 1,015 viajes reales.

---

## Qué está pendiente

### Módulo 4 — Para cerrar (prioridad alta)

- [ ] **`control.html`** — UI nueva con 4 tabs (sin_consolidar / subasta / activos / historial). Invoca las 9 functions vía Supabase RPC. **Siguiente paso natural.** 4-6h.
- [ ] **Smoke test SQL** antes de construir UI: consolidar 3 pedidos huérfanos → publicar → adjudicar manual. Validar que el pipeline cierra sin errores.
- [ ] **Promover Bernardo a `logxie_staff`** después de que se registre en netfleet.app:
  ```sql
  UPDATE perfiles SET tipo='logxie_staff', estado='aprobado'
   WHERE email='bernardoaristizabal@logxie.com';
  ```
- [ ] **Integración email** — decidir: n8n webhook vs Supabase Edge Function (Resend/SendGrid). Para `fn_publicar_viaje` + `fn_invitar_transportadora` + `fn_adjudicar_oferta`.
- [ ] **Deep-linking `transportador.html`**: query param `?viaje_ref=...` → scroll + highlight.
- [ ] **RLS endurecer en `viajes_consolidados`**: hoy `authenticated_all` permisivo. Cambiar a `subasta_tipo='abierta' OR existe invitación`.

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
- [x] ✅ Linker pedidos→viajes v2 con PEDIDOS_INCLUIDOS + canonicalización — 2026-04-17 (92% match)
- [ ] **Parser 4 — Pull Sheet ASIGNADOS cada 30min** → UPSERT en Supabase. Crítico para resolver snapshot drift.
- [ ] **Parser 2 — Pull Sheets de clientes externos** (Nivel 2 ingesta).
- [ ] **Parser 3 — Webhook HTTP** (Nivel 4 ingesta — CRM Avgust futuro).
- [ ] **Parser 1 — Email texto libre** (Nivel 1) — Gmail + Claude API extrae campos.

### Módulo 1 — Subasta (cerrar gaps)

- [x] ✅ Tabla `ofertas` creada — 2026-04-17
- [ ] Crear tablas `leads` y `cargas` (documentadas en CLAUDE.md pero no existen).
- [ ] Countdown y notificación de adjudicación en `transportador.html`.
- [ ] Fix formato `ofertas.viaje_id` — la tabla nueva usa UUID FK; el frontend legacy hitea por `viaje_rt` TEXT. Migrar frontend cuando se toque M1.

### Seguridad — 🔥 urgente

- [ ] **Rotar password de Supabase DB** — `Bjar1978*ABC` quedó en texto plano en esta sesión de chat. Dashboard → Project Settings → Database → Reset password.
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

1. **`control.html`** ← próximo ítem del roadmap. Backend M4 listo, solo falta UI.
2. **Smoke test SQL** opcional antes, para validar las 9 functions end-to-end.
3. **Decidir email backend** (n8n vs Edge Function) — bloqueante para `fn_publicar_viaje`.
4. **Rotar password Supabase** — no bloqueante pero urgente.

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

### Sensibilidades del sistema

- **Supabase anon key**: usar JWT largo (`iat:1775536019`). NUNCA `sb_publishable_`.
- **`estado: 'aprobado'`** (no `'activo'`) en `perfiles`. Frontend depende del string exacto.
- **Password DB**: comprometida al 2026-04-17. Rotar.

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
- Admin: https://netfleet.app/admin.html
- Último commit: `3f23453` — "feat: Módulo 4 backend completo"

---

*Última actualización: 2026-04-17 (sesión nocturna)*
