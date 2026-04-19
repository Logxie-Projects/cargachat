# Contexto de sesión — NETFLEET

---

## Fecha: 2026-04-17 (sesión tarde/noche)

### Qué se hizo

**1. Paso 1 del Módulo 4 — Schema foundational**
- Hallazgo crítico: tabla `perfiles` NUNCA existió en Supabase a pesar de estar documentada en CLAUDE.md. Sólo 3 users en `auth.users` sin fila correspondiente. El frontend (transportador/admin/empresa) venía tirando 404 silencioso contra `/rest/v1/perfiles` desde siempre.
- Creé `db/perfiles.sql` desde cero con diseño M4-compatible: 4 tipos (`transportador`, `empresa`, `logxie_staff`, `cliente_self_service`), FK `cliente_id`, CHECK de coherencia, trigger `handle_new_user` (lee `raw_user_meta_data`), helper `is_logxie_staff()` con SECURITY DEFINER (evita recursión en RLS), políticas RLS (usuario lee/edita propio, staff todo).
- Creé `db/modulo4_schema.sql`: `clientes.plan_bpo` (AVGUST+FATECO=true), tabla `acciones_operador` (audit trail con 4 índices + RLS).
- Commit: `e7bf564`.

**2. Fix de linker pedidos→viajes (bug Apps Script descubierto)**
- Usuario reportó que un consolidado en el Sheet tenía 3 pedidos (`TIT-00000182, TIT-199, TI-53482`) pero en Supabase solo aparecían 2.
- Diagnosticamos: el `raw_payload` del viaje tiene TODOS los 3 en `PEDIDOS_INCLUIDOS`, pero solo 2 en `CONSECUTIVOS_INCLUIDOS` (el Apps Script del Control Transporte los filtra mal — probablemente solo acepta prefijo `TIT-`). El migrador usó `CONSECUTIVOS_INCLUIDOS` como fuente, por eso faltaba uno.
- Creé `db/link_pedidos_viajes_v2.sql`: lee `raw_payload::jsonb->>'PEDIDOS_INCLUIDOS'` como fuente primaria, normaliza espacios internos (`TI -001966` → `TI-001966`), acepta `/` como separador además de `,`, compara por forma canónica (leading zeros ignorados: `TIT-00000182` ≡ `TIT-182`). Optimización crítica: CTE `viaje_refs` materializa pares `(viaje_id, canon_ref)` una sola vez antes del JOIN (evita parsear JSON 5M veces, baja de varios minutos a 0.9s).
- Resultado: **3463/3764 pedidos linkeados (92%)**, +X% vs v1. 301 huérfanos remanentes (pedidos nunca consolidados, o consolidaciones en el Sheet más nuevas que la última migración).
- Hallazgo de dominio: un pedido puede aparecer en múltiples viajes (reconsolidación cuando primer intento no se cargó). Linker prioriza `created_at DESC` correctamente. Guardado como memoria: `memory/project_reconsolidacion.md`.

**3. Paso 2-3 del Módulo 4 — Backend completo**
- Discusión de diseño: definimos el modelo multi-cliente/multi-transportadora end-to-end. Confirmamos que agregar columnas en Postgres es barato (por nombre, no posición — 0 breakage del frontend). Decidimos arquitectura `public.*` (operacional) + `tracking.*` (eventos, append-only, futuro M3).
- Discusión de scope M4: 9 operaciones en lugar de 5 originales. Agregado: `fn_agregar_pedido_a_viaje`, `fn_quitar_pedido_de_viaje`, `fn_invitar_transportadora`, `fn_asignar_transportadora_directo`. Subastas `abierta` vs `cerrada` (invite-only).
- Creé `db/modulo4_schema_extra.sql`: tabla `transportadoras` (7 seed: ENTRAPETROL, TRASAMER, JR, Trans Nueva Colombia, PRACARGO, Global, Vigía), tabla `ofertas` (Módulo 1, con RLS `read_own_or_staff`), tabla `invitaciones_subasta`. ALTERs a `viajes_consolidados`: +6 cols (`subasta_tipo`, `publicado_at`, `adjudicado_at`, `oferta_ganadora_id`, `adjudicacion_tipo`, `transportadora_id`). CHECK de `acciones_operador.accion` extendido.
- Bug encontrado + fix en vivo: mi DO block para dropear CHECK usaba `ILIKE '%accion%IN%'` pero Postgres normaliza `IN (...)` a `= ANY(ARRAY[...])`. Cambié a `ILIKE '%accion%'` y pasó.
- Creé `db/modulo4_functions.sql`: **9 functions + helper `_recalc_viaje_agregados`**. Todas `SECURITY DEFINER` con gate `is_logxie_staff()` al inicio, audit a `acciones_operador`, transaccionales. Formato nuevo de `viaje_ref`: `NF-YYMMDD-HHMMSS-XXXX`.
- Commit: `3f23453`.

### Estado final de la sesión

**Base de datos Supabase (al cierre):**
- Tablas `public`: `clientes` (2), `perfiles` (0), `viajes_consolidados` (1281 legacy), `pedidos` (3764, 92% linkeados), `acciones_operador` (0), `transportadoras` (7 seed), `ofertas` (0), `invitaciones_subasta` (0).
- 9 functions M4 listas (`fn_*`) + helpers.
- Falta: `leads`, `cargas`, y tablas futuras de `tracking.*` (M3).

**Frontend Supabase-dependiente (al cierre):**
- `transportador.html`, `admin.html`, `empresa.html`, `mis-ofertas.html` están hitting tablas que ahora SÍ existen (`perfiles`, `ofertas`). Potencialmente empiezan a funcionar sin cambios, o muestran nuevos bugs reales (antes todo fallaba silencioso). **Validar en próxima sesión.**

### Lo que quedó pendiente (para próxima sesión)

**Prioridad alta (M4 para cerrar):**
1. **`control.html`** — UI nueva con 4 tabs (sin_consolidar / subasta / activos / historial) que invoca las 9 functions vía Supabase RPC. 4-6h de trabajo.
2. **Smoke test backend** (opcional antes de UI): consolidar 3 pedidos huérfanos existentes vía SQL → publicar → adjudicar manual → verificar que el pipeline cierra sin error.
3. **Promover Bernardo a `logxie_staff`**: después de registrarse en netfleet.app correr:
   ```sql
   UPDATE perfiles SET tipo='logxie_staff', estado='aprobado'
    WHERE email='bernardoaristizabal@logxie.com';
   ```

**Prioridad media:**
4. **Deep-linking en `transportador.html`** — `?viaje_ref=...` hace scroll y highlight.
5. **Integración email** para `fn_publicar_viaje` / `fn_invitar_transportadora` / `fn_adjudicar_oferta` — decidir: n8n webhook vs Supabase Edge Function con Resend/SendGrid.
6. **RLS endurecer en `viajes_consolidados`** — hoy `authenticated_all` deja todo abierto. Cambiar para que transportador solo vea `subasta_tipo='abierta' OR existe invitación`.

**Prioridad baja:**
7. **Crear tablas `leads` y `cargas`** (Módulo 1 residual).
8. **M3 completo**: schema `tracking.*` con `entregas` (N intentos por pedido), `eventos_viaje` (cargue/descargue timestamps), `checkins`. Reemplaza AppSheet "Donde Está Mi Pedido" + "NAVEGADOR".
9. **Snapshot drift del Sheet**: los 301 pedidos huérfanos y el caso del usuario (viaje 2026-01-30 recién agregado al Sheet pero no a Supabase) son síntomas de que la migración es un snapshot puntual. Solución: Parser 4 de M2 (pull Sheet ASIGNADOS cada 30 min).

### Notas operativas de la sesión

- **DATABASE_URL pooler correcto:** `postgresql://postgres.pzouapqnvllaaqnmnlbs:Bjar1978%2AABC@aws-1-us-east-1.pooler.supabase.com:5432/postgres` (región `aws-1-us-east-1`, NO `aws-0-us-east-1`; user `postgres.pzouapqnvllaaqnmnlbs` CON el punto). Direct connection (`db.pzouapqnvllaaqnmnlbs.supabase.co`) NO resuelve DNS — proyecto solo acepta pooler. `*` en password debe ir URL-encoded como `%2A`.
- **Password comprometida:** `Bjar1978*ABC` quedó en el chat en texto plano (3x). Rotar desde Supabase Dashboard → Database → Reset password ANTES de seguir.
- **PowerShell no persiste `$env:`** entre sesiones. Hay que resetearlo cada vez.
- **Perfiles previos que nunca existieron:** si algún frontend empieza a fallar en prod porque ahora sí existen las tablas pero con schema distinto al que esperaba, revisar cada fetch contra `/rest/v1/perfiles` y `/rest/v1/ofertas`.

### Prompt sugerido para abrir la próxima sesión

```
Lee CLAUDE.md y docs/CONTEXTO_OPERATIVO.md del repo D:\NETFLEET
(github.com/Logxie-Projects/cargachat branch main).

Último commit: 3f23453 — Módulo 4 backend completo.

Estado: 9 Postgres functions del M4 listas + tablas transportadoras/ofertas/invitaciones.
Arquitectura de subasta (abierta/cerrada/directa) funcional a nivel DB.

Quiero seguir con Módulo 4: construir control.html (UI staff logxie) con
4 tabs que invoca las functions fn_* vía Supabase RPC. Antes, hacer smoke
test SQL para validar que las functions cierran el ciclo sin errores.
```

---

## Fecha: 2026-04-08

## Qué es NETFLEET
Marketplace de carga B2B para Colombia. Conecta empresas (generadores de carga) con transportadores. Landing page estática (HTML/CSS/JS) sin framework ni bundler.

## Stack
- **Hosting**: Cloudflare Pages (`netfleet.app`). GitHub repo `Logxie-Projects/cargachat`, branch `main`.
- **Auth + DB**: Supabase (`pzouapqnvllaaqnmnlbs.supabase.co`)
- **Viajes**: Google Sheets publicado como CSV → la página lo lee al cargar
- **Precios**: n8n procesa emails → calcula precio con Distance Matrix API → escribe en Sheet
- **Mapas**: Leaflet + CartoDB tiles + OSRM (rutas reales) + Google Geocoding API

## Archivos principales
- `index.html` — Landing principal (~2000+ líneas)
- `panel.html` — Panel del transportador (mis ofertas) — NUEVO
- `viaje.html` — Tarjeta individual de viaje (para screenshots LinkedIn)
- `supabase.min.js` — SDK Supabase v2.39.8 bundled
- `modeloprecion8n.txt` — Código del nodo de precio en n8n (v1, viejo)
- `modeloprecion8n_v2.txt` — Código actualizado del nodo de precio en n8n (v2, nuevo)
- `ViajesColombia.xlsx` — Dataset de 1,015 viajes reales para entrenamiento ML
- `supabase_ofertas.sql` — SQL para crear tabla `ofertas` (ya ejecutado)
- `test_osrm.html` — Demo de rutas reales por carretera
- `ruta_debug.html` — Debug visual del algoritmo 2-opt

## Lo que se hizo en esta sesión (en orden)

### 1. Análisis del estimador de flete
- Revisé la calculadora existente: fórmula lineal `3016*km + 156*kg + 100469`
- Encontré bugs en el algoritmo 2-opt de ordenamiento de rutas
- Identifiqué que no usa distancias reales por carretera (solo línea recta)

### 2. Modelo ML de precios (reemplaza fórmula lineal)
- Cargué `ViajesColombia.xlsx` (1,015 viajes reales, 7 columnas)
- Entrené modelo Ridge polinomial grado 2: `base = 3097.69*km + 217.94*kg + 0.1215*km*kg - 1.0566*km² - 0.0034*kg² + 63186*paradas + ajusteZona - 306248`
- R² = 0.919, MAE = $568K (vs $641K / 0.861 de la fórmula vieja)
- Implementé en el frontend con sliders (km, kg, paradas) + dropdown de zona

### 3. Zonas del modelo
Ajustes aditivos en COP por zona:
```
HUB: 0, ANTIOQUIA: 15759, BOYACA: 87756, CENTRO: 22045,
CUNDINAMARCA: 65602, EJE CAFETERO: -18794, LLANOS: 159210,
NORTE: 79189, OCCIDENTE: 10720, ORIENTE: -176447,
SANTANDERES: -213483, SUR: 79189, TOLHUIL: -18146, VALLE: 34226
```

### 4. Actualización de n8n
- Creé `modeloprecion8n_v2.txt` con la misma fórmula polinomial + detección de zona por ciudades + paradas
- El usuario actualizó manualmente el nodo en n8n
- Mantiene: precios fijos Buenaventura, techo 2.8% valor mercancía, mínimo $950K

### 5. Alineación estimador ↔ n8n
- Misma fórmula exacta en ambos (diferencia $0 con mismos inputs)
- Auto-detección de zona al seleccionar un viaje (mapea ciudades de destino a zona)
- Hub detection: si origen Y destino son bodegas (funza/yumbo/espinal)
- Siempre actualiza sliders al seleccionar viaje (fix km=0 para viajes cortos)
- Precio mínimo $950K en el estimador (match con n8n)
- Eliminados piso (-15%) y techo (+15%) del estimador — modelo colaborativo
- Agregado badge "Ahorra hasta X%" comparando vs p75 histórico

### 6. Urgencia en tarjetas de viaje
- Badge dinámico basado en fecha_cargue (no en posición del array):
  - ⚡ Urgente (rojo, pulso CSS): fecha pasada o hoy
  - 🔥 Cierra pronto (naranja): 1-2 días
  - ⏳ Subasta abierta (verde): 3-5 días
  - ✓ Disponible (verde): 6+ días
- Countdown text: "Cargue inmediato", "Cierra en X días", "Carga en X días"
- Fecha muestra "Hoy" para cargue inmediato

### 7. Polling de viajes nuevos
- Cada 3 minutos hace fetch silencioso al CSV
- Si hay viajes nuevos → banner navy "🔔 X viajes nuevos — Ver ahora"
- Click en banner → actualiza tarjetas y mapa sin recargar página
- Banner con animación slide-down

### 8. Rutas reales por carretera (OSRM)
- Integrado OSRM (gratis, sin API key) en el mapa principal
- Muestra línea recta punteada inmediatamente, reemplaza con ruta real cuando OSRM responde
- Fallback automático a línea recta si OSRM falla (timeout 5s)
- `test_osrm.html` disponible como demo independiente

### 9. Sistema de subastas (Supabase)
- **Tabla `ofertas`** en Supabase (ya creada):
  - id, viaje_rt, usuario_id, nombre, empresa, telefono, precio_oferta, comentario, estado, created_at
  - RLS activado, unique index (1 oferta activa por usuario por viaje)
  - Estados: activa, aceptada, rechazada, cancelada
- **Modal de oferta** en index.html (reemplazó Google Forms):
  - Se abre al hacer clic en "Aceptar" o "Hacer oferta"
  - Muestra resumen del viaje, input de precio con formato automático, comentario opcional
  - "Aceptar" pre-llena precio base, "Oferta" deja vacío
  - Requiere auth (redirige a login/registro si no logueado)
- **Conteo de ofertas** en tarjetas: "● 3 ofertas recibidas" (punto verde pulsante)
- **ID de viaje**: generado como hash de origen+destino+fecha+peso (el CSV no tiene RT_TOTAL)

### 10. Panel del transportador (panel.html) — NUEVO
- Página separada `panel.html` — base para futura app
- Tabs: Activas / Historial
- Stats: ofertas activas, aceptadas, total
- Cada oferta muestra datos completos del viaje (cruza con CSV del Sheet)
- Cancelar ofertas activas
- Auth-gated (misma sesión Supabase que index.html)
- Link "Mis ofertas" en nav de index.html cuando está logueado
- **PENDIENTE**: el fetch al CSV falla con CORS cuando se abre local (file://). Funciona desde hosting real.

## Pendientes / Issues conocidos
1. ~~Confirmar URL de hosting~~ — **Confirmado: Cloudflare Pages → netfleet.app**
2. **panel.html CORS** — funciona en hosting, no en file://
3. **Viajes viejos** en el Sheet tienen precio calculado con n8n v1 (fórmula vieja) — solo viajes nuevos usarán v2
4. **Bug 2-opt** en index.html línea 1483: fallback de `pts[j+1]` cuando j es último índice
5. **viaje.html** sigue usando sort por latitud en vez de nearest-neighbor/2-opt
6. **Rangos históricos** del estimador son estáticos — podrían actualizarse periódicamente con datos nuevos

## Credenciales / URLs
- Supabase URL: `https://pzouapqnvllaaqnmnlbs.supabase.co`
- Supabase anon key: en index.html línea 775
- Google Maps API key: en index.html línea 926
- CSV URL (Sheet público): en index.html línea 923
- GitHub: `https://github.com/Logxie-Projects/cargachat.git` (repo mantiene nombre cargachat, dominio es netfleet.app)

---

## Fecha: 2026-04-17 / 18 (sesión larga — control.html iteraciones)

### Qué se hizo

**1. Bernardo se registró en Netfleet como `logxie_staff`**
- Detectamos que su user (`fa822bae-4743-4d40-95cf-c9fdd815214f`) ya existía en `auth.users` pero sin fila en `perfiles`. INSERT manual de perfil `logxie_staff, aprobado`. También INSERT de los otros 2 users como `transportador, pendiente`.

**2. RLS `clientes` — fix pequeño con impacto grande**
- control.html mostraba "5325d9" (UUID truncado) en vez de "AVGUST". Causa: RLS original solo permitía `service_role` leer `clientes`. Creé `db/clientes_rls_staff.sql` con policies `staff_read`, `staff_write`, `self_service_read_own`.

**3. Iteraciones de UI sobre control.html (muchas)**
Fix tras fix basado en feedback en vivo:
- **Filtro de fechas**: desde/hasta + presets 7d/30d/90d en tab Sin consolidar.
- **Agrupar por origen**: filas header azules con checkbox "seleccionar grupo" + subtotal (# pedidos, kg, valor, rango fechas).
- **Fix timezone fmtFecha**: `'2026-04-10'` mostraba "9 abr" por conversión UTC→COT. Fix: `timeZone:'UTC'`.
- **Prioridad bajo ruta**: en vez de observaciones truncadas, ahora muestra `p.prioridad` como badge colorido (URGENTE rojo, ALTA naranja, NORMAL azul). Llama_antes como flag naranja.
- **Cliente bajo RM**: cambio a `p.cliente_nombre` (receptor final como "INGENIO DEL CAUCA SAS"), no `AVGUST/FATECO`.
- **Botón `ℹ` + modal detalle pedido**: embalaje (contenedores/cajas/bidones/canecas/unidades), contacto, dirección, horario, motivo, vendedor, coordinador, observaciones.
- **Sección "Pedidos incluidos" en viaje cards**: cada pedido del viaje colapsable con todo el detalle. Útil para transportador que adjudique.
- **Stats por viaje**: $/kg, $/km, $/pedido, %flete-vs-valor (rojo si >3%).
- **2 filas de aggregates en tab Consolidados**: total/borradores/ofertas/flete + peso total/# pedidos/prom $/kg/prom flete%.
- **Tags adjudicación**: 🏆 subasta (dorado) vs 📌 directa (violeta) en tab Activos.
- **Badge "borrador"** + botón "Publicar" inline en cards de viajes no publicados (antes desaparecían de la UI).
- **Auto-switch de tab** tras cada acción (adjudicar→Activos, reabrir→Consolidados). Toasts descriptivos con nombre del proveedor.
- **Toggle "incluir migrados Sheet ASIGNADOS"** en Consolidados (los 1281 históricos estaban ocultos por default).
- **Fix problema silencioso**: fetch pedidos solo devolvía 58 porque PostgREST limita a 1000 rows. Fix: 2 queries separadas (sin_consolidar + viaje_id IS NOT NULL), merge con dedupe por id.
- **Fix campo Consecutivos truncado**: removido del info grid del viaje (redundante con "Pedidos incluidos").

**4. `fn_reabrir_viaje(viaje_id, razon)` — Módulo 4 nueva función**
- Bernardo preguntó: si el proveedor queda mal después de adjudicar/asignar, ¿cómo corrijo? Hoy todas las functions gatean en `estado='pendiente'`.
- Creé `db/modulo4_reabrir.sql`: `fn_reabrir_viaje` revierte `confirmado → pendiente`. Libera `transportadora_id`, `adjudicado_at`, `adjudicacion_tipo`, `oferta_ganadora_id`. Si adjudicación fue por subasta, reactiva ofertas (aceptada+rechazadas → activa). Pedidos `asignado → consolidado`. Solo funciona sobre `confirmado` (en_ruta/entregado bloqueado). CHECK de `acciones_operador.accion` extendido con 'reabrir'.
- UI: botón "↩ Reabrir" en Activos con `prompt()` para razón. Auto-switch a Consolidados después.

**5. Commits finales de esta tanda**
- `75c9df2` feat: filtro fecha_cargue + presets
- `6dfc828` feat: agrupar por origen + fix timezone
- `aeb88bc` fix: borradores visibles + prioridad en pedidos + RLS clientes
- `2c10220` feat: detalle completo pedidos + Consolidados + tags adjudicación
- `6793556` feat: reabrir viajes confirmados + auto-switch + fixes varios
- `6d642d4` feat: estadísticas de viaje ($/kg, $/km, etc.)

### Riesgos y detalles frágiles
- El gate `is_logxie_staff()` requiere `auth.uid()` del JWT. Si el Python script se conecta como `postgres` directo (sin JWT), falla. Solución: extender gate para aceptar `session_user IN ('postgres','supabase_admin')` (hecho en la siguiente sesión).
- `_norm_empresa` no existía aún — había 82 filas con "FATECO, AVGUST" que Bernardo notó visualmente.

---

## Fecha: 2026-04-19 (sesión sync Sheets↔Netfleet)

### Qué se hizo

**1. Diseño del sync bidireccional (decisiones de Bernardo)**
- Sync AppSheet/Sheets → Netfleet, unidireccional. Durante transición, AppSheet sigue siendo primario; Netfleet refleja.
- **Cadencia**: 15 min automático + botón manual on-demand en control.html.
- **Sheet nunca elimina**: pedidos eliminados se marcan "Cancelado" → se propaga a Netfleet.
- **Conflicto "Netfleet gana"**: viajes con `fuente='netfleet'` nunca se sobrescriben por el sync.
- Arquitectura: Postgres functions (lógica centralizada), n8n cron (disparo), botón UI (manual), script Python (backfill inicial).

**2. Postgres functions de sync**
- `fn_sync_viajes_batch(jsonb)`: UPSERT batch por `viaje_ref`. Reglas: Netfleet skip, terminales skip, cancelado propaga. Audit con counters (insertados, actualizados, saltados_netfleet, saltados_terminal, marcados_cancelado, errores, err_samples).
- `fn_sync_pedidos_batch(jsonb)`: UPSERT batch. Match por `(cliente_id, pedido_ref)` más reciente no-terminal. Handle de duplicados legítimos (re-entradas cancelaciones/correcciones).
- Gate extendido: acepta `is_logxie_staff() OR current_setting('role')='service_role' OR session_user IN ('postgres','supabase_admin')`.
- Mapeo de 29 campos ASIGNADOS → viajes, 41 Base_inicio-def → pedidos. Verificado que TODOS existen en schema tras diagnóstico de columnas.
- Helpers `_norm_estado_viaje(text)` y `_norm_estado_pedido(text)` mapean estados crudos del Sheet (`EJECUTADO`, `EN RUTA`, `PENDIENTE`) a canónicos.

**3. Script Python `sync_from_csv.py`**
- CLI que lee CSV, mapea columnas Sheet → payload canónico, llama RPCs en batches de 500.
- Flag `--truncate` para migración limpia. Pide confirmación interactiva. Drop NOT NULL de `cliente_id` temporalmente, TRUNCATE CASCADE, sync, post_migration.sql (backfill + restore NOT NULL), linker v2.
- Normaliza headers (trim whitespace) — Sheets exporta con espacios inconsistentes (" PEDIDOS_INCLUIDOS", "ESTADO ", etc.).
- Parser de fechas robusto (múltiples formatos: ISO, DD/MM/YYYY, MM/DD/YYYY, con y sin hora).

**4. Discrepancia del fantasma (928 viajes)**
- Bernardo reportó 2209 filas en ASIGNADOS vs 1281 en Supabase.
- Investigación: `=CONTARA(A:A)` en el Sheet = 1283 (+ header = 1282 filas reales).
- Las filas 1284-2210 son **filas fantasma** (formato de celdas aplicado pero sin datos — típico de AppSheet cuando "borra" filas).
- **Conclusión**: no faltaba data. Supabase estaba 100% alineado con el Sheet real.

**5. Backfill fresh**
- Bernardo pidió limpieza total. TRUNCATE + sync completo desde CSVs:
  - 1281 viajes importados (100%)
  - 3740 pedidos importados (40 menos que 3780 del CSV por duplicados legítimos de `pedido_ref`)
  - 94.7% linkeados (3543 con viaje_id, 197 huérfanos, 128 viajes vacíos)
- Todos los viajes migrados quedan `fuente='sheet_asignados'`. 0 netfleet tests sobrevivieron.

**6. Normalizador de empresa**
- Bernardo notó 4 variantes: AVGUST, FATECO, "AVGUST, FATECO", "FATECO, AVGUST" (+7 con espacio extra).
- `_norm_empresa(text)`: split coma, trim, upper, dedupe, sort asc, join ", ". Tests inline con ASSERT.
- Integrado en las 4 rutas de escritura (UPDATE viajes, INSERT viajes, UPDATE pedidos, INSERT pedidos). **Previene recurrencia en futuros syncs**.
- UPDATE one-shot ejecutado: 82 filas "FATECO, AVGUST" → "AVGUST, FATECO". Resultado final: 3 variantes canónicas (AVGUST 688, AVGUST+FATECO 320, FATECO 273).

**7. Commits**
- `f039826` feat: sync Sheets→Netfleet + toggle migrados + control.html improvements
- `920b457` feat: normalizador de empresa en fn_sync_*_batch

### Estado final
- BD limpia y sincronizada
- control.html en producción con toggle para ver los 1281 migrados
- Sync functions listas, esperan trigger (n8n) o botón (UI)

### Próximo paso
- **n8n workflow cron 15min + webhook manual** → para que el sync corra automático
- **Botón 🔄 Sync en control.html** → disparo on-demand via webhook
- Con eso: AppSheet → Netfleet 100% automático sin intervención manual

### Riesgos y detalles frágiles
- Si Sheet cambia nombres de columnas, el mapping Python rompe silenciosamente (warn pero no falla). Revisar headers después de cualquier refactor en AppSheet.
- El Python script corre como postgres superuser (via pooler), bypassa RLS. OK para backfill, no para prod. El cron n8n debe usar service_role token (no postgres).
- Dumps en `dumps/` están gitignored — contienen PII (contactos, direcciones, NITs).
