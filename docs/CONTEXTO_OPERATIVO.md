# Estado actual Netfleet

> Foto del proyecto al **2026-04-24 (tras overhaul analizador + doble confirm consolidar directo)**.

---

## 🗓️ Próximas sesiones (en orden recomendado)

> Cuando abras nueva sesión, revisá acá qué bloque sigue. Cada bloque es una sesión independiente, commit-atómico end-to-end. Copiá el prompt tal cual al chat de Claude.

### ✅ Sesión A — COMPLETADA (2026-04-23): Sub-tab 👥 Usuarios en Catálogo
Ver TL;DR abajo.

### ✅ Sesión C — COMPLETADA (2026-04-23 tarde/noche): Overhaul analizador-rutas.html
18 commits con fixes de KPIs, reprogramación secuencial, parser horario, pedidos sintéticos/prestados, OSRM fallback, input búsqueda RT. Ver TL;DR abajo.

### ✅ Sesión E (parte 1) — COMPLETADA (2026-04-24): Fork BETA + multi-vehículo MVP

Fork `analizador-rutas-beta.html` (estable intacto, link 🧪 BETA en header). Implementa:
- **Inputs deadline (h) + capacidad/veh (kg)** — defaults 24h / 8500 kg
- **Pase 1**: corre el plan completo con todos los dests para obtener duración REAL (con ventanas/pernoctas/standby) — NO un estimador sintético
- **Pase 2 con k-means geográfico**: si excede deadline o capacidad, agrupa por proximidad ENTRE destinos (no por distancia al origen — el chunk-by-distance generaba absurdos como "dest a 100km del resto del vehículo cuando otro vehículo lo tenía a 20km")
- **1 mapa unificado, 2 colores**: V1 cyan + V2 naranja superpuestos en el mismo mapa Leaflet, fitBounds combinado
- **2 timelines apilados verticalmente**, cada uno con header sticky destacado del color del vehículo ("🚚 VEHÍCULO 1 — N dest · Xh Ymin")
- **Truck mode realista** (hardcoded): velocidad 35 km/h reemplaza OSRM (autos), +60min salida planta → carretera, +15min/destino entrada urbana, descMin auto-ajustado por direcciones únicas (Villapinzón con 3 dirs = 3×60+2×15=210min vs 60min default), admin extra +20min/pedido a misma dirección
- **Validación post-Pase 2**: lee duración real de V1/V2, muestra warning rojo si exceden deadline ("V1=76h V2=81h ambos exceden 24h, harían falta ~7 vehículos") o ✓ verde si cumplen

**Limitación conocida**: layout actual soporta solo V1+V2. Para deadlines estrictos (24h con consolidaciones grandes) frecuentemente harán falta 3+ vehículos — sesión E parte 2 implementa multi-N dinámico + bucle de re-clustering.

Commits: `b0ebe18` (fork inicial) + commit final sesión 1.

---

### 🎯 Sesión E (parte 2) — **Multi-vehículo N dinámico (3+) + tracking real vs planeado** — pendiente

**Objetivo**: cerrar el plan original de 3 sesiones que quedó parcial en parte 1. Soporte para 3+ vehículos cuando el deadline real lo requiere + persistencia de horarios reales para comparar vs planeado.

**Lo que YA ESTÁ hecho** (sesión E parte 1, no re-construir):
- Fork BETA con link bidireccional al estable
- Inputs deadline + capacidad
- Pase 1 con dur real, pase 2 con k-means
- 1 mapa con 2 colores, 2 timelines apilados con headers destacados
- Truck mode realista (35 km/h, overheads salida/entrada, descMin por dirs/pedidos)
- Warning honesto si exceden deadline + sugerencia de N reales

**Lo que falta** (parte 2):

A) **Multi-N dinámico (3+ vehículos)**:
- Refactor de layout: contenedor `vehiclesContainer` con N paneles dinámicos en lugar de 2 fixed rows
- Mapa unificado con N colores distintos por vehículo (paleta cyan/naranja/violeta/verde/rojo/...)
- Bucle iterativo de re-clustering: si V1 con k=2 excede deadline, probar k=3, k=4... hasta cap (15) o todos cumplen
- Drag&drop entre vehículos (mover dest de V1 a V3, etc.) — recalc on drop

B) **Tracking real vs planeado** (sesión 3 original):
- Schema Supabase: `seguimiento_entregas` (id, pedido_id FK, vehiculo_num, hora_planeada_llegada, hora_real_llegada, hora_real_salida, notas, capturado_por, capturado_at)
- RPC `fn_seguimiento_upsert` con audit
- Inputs ⏱ por entrega en cada timeline → al guardar persiste + muestra delta vs plan
- Vista comparativa: % on-time, deltas promedio por vehículo

**Prompt para copiar al chat**:
```
Lee CLAUDE.md y docs/CONTEXTO_OPERATIVO.md (obligatorios).
TL;DR sesión E parte 1 (multi-vehículo MVP) + qué falta para parte 2.

OBJETIVO sesión E parte 2: completar el BETA del analizador.
Hoy soporta solo V1+V2; muchos casos reales necesitan 3+ vehículos.
Más: persistir horarios reales por entrega para comparar vs planeado.

LO QUE YA FUNCIONA (no re-construir):
- analizador-rutas-beta.html con inputs deadline+capacidad
- Pase 1 dur real + pase 2 k-means
- 1 mapa con 2 colores (V1 cyan + V2 naranja), 2 timelines apilados
- Truck mode (35 km/h, +60min salida, +15min/dest entrada urbana)
- descMin auto-ajustado por direcciones únicas + admin pedidos extra
- Warning honesto si V1/V2 exceden deadline + sugerencia N

PENDIENTE (parte 2):
1. Multi-N dinámico: refactor layout a contenedor con N paneles, bucle
   re-clustering hasta encontrar k que cumple, drag&drop entre vehículos
2. Tracking real vs planeado: tabla supabase seguimiento_entregas,
   RPC upsert, inputs ⏱ en cada timeline con delta vs plan

¿Por dónde arrancamos? Multi-N primero (cierra el feature core)
o tracking primero (Bernardo lo pidió como deliverable principal)?

Cuenta staff: bernardoaristizabal@logxie.com
```

---

### 🎯 Sesión E (parte 1 original — ahora descompuesta) — **Ajustes adicionales al analizador estable** — sin estimado

**Objetivo**: atacar las deudas documentadas del analizador + cualquier ajuste que Bernardo encuentre al usarlo en producción con viajes reales.

**Lo que YA ESTÁ hecho** (para no re-construir):
- Canonización 191 ciudades + 10 corredores (netfleet-core.js)
- KPIs realistas (duración total cargue→últ entrega, extracostos rojos con viáticos+standby, descargue real)
- Reprogramación secuencial respetando ventanas de clientes (drive time, no todos a 8 AM)
- Día standby visible entre primer y último día
- Return event se mueve al final del timeline (suma drive real desde últ reprog al origen)
- Parser horario con AM/PM/M/mediodía + fallback a observaciones + filtro de direcciones/teléfonos
- Pedidos sintéticos para destinos en v.destino sin pedido linkeado
- Pedidos "prestados" via v.consecutivos para viajes duplicados (TR REEMPLAZADA + real)
- OSRM fallback haversine a 30 km/h con banner "⚠ aproximado"
- Input "Buscar por RT" en sidebar (bypasa limit 100, ILIKE)
- Ediciones manuales (priority/descMin/ventanas/días) marcan userReorderedFlag=true

**Deudas abiertas documentadas**:
1. **Parser sabatino** — cuando observación dice `"L-V 8am-5:30pm. Sábado 8am-11am"` el parser toma las 2 primeras ventanas sin distinguir día (v2 queda como Sábado incorrectamente). Requiere segmentación por día (sección L-V vs Sábado).
2. **Linker v6 TR REEMPLAZADA** — 84 viajes legacy con `proveedor='TR REEMPLAZADA'` (placeholders del AppSheet). El linker v3/v4 a veces asigna pedidos al TR REEMPLAZADA en lugar del viaje real hermano. Fix propuesto: Postgres function que re-linkea pedidos, integrada al chain `fn_run_linkers`.
3. **Verificar en producción** que "netfleet.app/analizador-rutas.html" cargue viajes/pedidos correctamente. Al final de sesión anterior Bernardo reportó "no cargó" — probablemente cache/sesión, sin stack trace.
4. **Test E2E de user reorder**: marcar priority / editar ventanas / cambiar días → "Recalcular con tu orden" → fila USR (abajo) se actualiza correctamente. Fix hecho pero sin verificación end-to-end.

**Prompt para copiar al chat**:
```
Lee CLAUDE.md y docs/CONTEXTO_OPERATIVO.md (obligatorios).
Especialmente el TL;DR "overhaul analizador-rutas.html"
(sesión 2026-04-23 tarde/noche) para contexto de los últimos
~20 commits relacionados al analizador.

OBJETIVO: ajustes al analizador de rutas (analizador-rutas.html).

CONTEXTO RÁPIDO (qué YA funciona, no re-construir):
- Canonización 191 ciudades (netfleet-core.js CIUDADES + CORREDORES)
- KPIs realistas: Duración total, Extracostos (viáticos+standby rojo),
  descargue real por destino
- Reprogramación secuencial respetando ventanas (drive time entre reprogs)
- Día standby visible (sáb+dom cerrados visibles como fila)
- Return event al final del timeline
- Parser horario AM/PM/M con fallback a observaciones + filtro direcciones
- Pedidos sintéticos + "prestados" (viajes duplicados)
- OSRM fallback haversine 30 km/h
- Input "Buscar por RT" en sidebar
- userReorderedFlag en priority/descMin/ventanas/días

DEUDAS ABIERTAS (posibles ajustes):
1. Parser sabatino (segmentación L-V vs Sábado)
2. Linker v6 TR REEMPLAZADA (84 viajes legacy con placeholder)
3. Investigar "netfleet no cargó" reportado al cierre anterior
4. Test E2E user reorder (priority/ventanas en fila USR)

Te paso qué específicamente quiero ajustar.

Cuenta staff: bernardoaristizabal@logxie.com
```

---

### 🎯 Sesión C-OLD — COMPLETADA — **Auditoría funcional Pedidos + Viajes (control.html)**

**Objetivo**: revisar con Bernardo, tab por tab, qué de lo que existe hoy se usa en la operación real, qué falta, y qué es candidato a eliminar. La base del panel creció mucho en los últimos días (pistas LogxIA, agrupar por ruta, sub-totales, hints, Scenarios, bloque tracking, Drive API para cumplidos) — hay que hacer un pase de consolidación antes de seguir construyendo arriba.

**Scope cerrado**: solo tabs `📥 Pedidos` y `🚚 Viajes` de `control.html`. NO tocamos mi-netfleet, NO tocamos Catálogo, NO features nuevos.

**Orden**:
1. Pedidos primero (tira de pistas · filtros · agrupaciones · sub-totales · hints · bulk actions · columnas · modales).
2. Cuando Pedidos quede aprobado end-to-end, pasamos a Viajes (Subasta · Activos · Archivo · Scenarios).
3. No se pasa a código hasta tener la lista de cambios confirmada.

**Criterios de done**:
- [ ] Tab Pedidos: tabla `✅ funciona como está · 🔧 falta o ajustar · 🗑 candidato eliminar` revisada ítem por ítem con Bernardo
- [ ] Tab Viajes: misma tabla para Subasta + Activos + Archivo + Scenarios
- [ ] Commits atómicos con SOLO los cambios confirmados — uno al cerrar Pedidos, otro al cerrar Viajes
- [ ] Nada eliminado sin confirmación explícita de Bernardo (regla dura de la sesión)

**Prompt para copiar al chat**:
```
Lee CLAUDE.md y docs/CONTEXTO_OPERATIVO.md (obligatorios).
Si en algún punto tocamos schema/DB, sumá docs/ARQUITECTURA.md.
Si surgen dudas de autopilot o reglas LogxIA, leé docs/LOGXIA_JOURNEY.md.

OBJETIVO DE LA SESIÓN: auditoría funcional del panel control
(netfleet.app/control.html), específicamente tabs Pedidos y Viajes.
Garantizar que la UI refleja la operación real y sacar lo que sobra.

ORDEN:
1. 📥 PEDIDOS primero. Revisamos juntos qué está, qué falta, qué sobra.
2. Después 🚚 VIAJES (Subasta + Activos + Archivo + Scenarios).
3. No pasamos a código hasta que el tab en curso esté completamente claro.

REGLAS DURAS:
- NO borrar ningún campo, columna, filtro, función, botón, tile, hint o
  lógica sin pedir permiso EXPLÍCITO. Si sospechás que algo no se usa,
  preguntá con evidencia antes de proponer eliminación.
- Ante duda entre "sobra" vs "se usa rara vez", default = CONSERVAR.
- Cada cambio con mi OK item por item. No bloques grandes.
- Si proponés eliminar, mostrame: (1) qué es, (2) dónde se usa hoy, (3)
  por qué creés que sobra, (4) qué se pierde si se va.

MODO DE TRABAJO:
- Arranco describiéndote qué veo en pantalla o pasando screenshots.
- Vos me hacés preguntas para entender el uso real antes de opinar.
- Vamos armando 3 columnas por tab:
    ✅ funciona bien como está
    🔧 falta algo o se debe ajustar
    🗑 candidato a eliminar (requiere mi OK)
- Cuando cerremos Pedidos, commit atómico con SOLO los cambios
  confirmados. Después pasamos a Viajes.

ESTE ES EL ALCANCE — NO se atacan B (Asignar recursos al viaje) ni D
(LogxIA Fase 1) en esta sesión. Ver "Próximas sesiones" en
CONTEXTO_OPERATIVO.md para ese orden.

Cuenta test transportadora: bernardojaristizabal@gmail.com / 123ABC
Cuenta staff: bernardoaristizabal@logxie.com
```

---

### 🎯 Sesión siguiente (A-OLD, reemplazada): **Sub-tab 👥 Usuarios en Catálogo** — ~1h 50min

**Objetivo**: Bernardo crea y administra cuentas de transportadoras y staff desde `control.html` → 🏢 Catálogo → 👥 Usuarios (hoy placeholder). Edge Function con `service_role` + UI inline. Cierra el onboarding — a partir de acá el link `netfleet.app/mi-netfleet.html` se puede compartir por WhatsApp con credenciales.

**Criterios de done**:
- [ ] Desde Catálogo creo cuenta JEIMMY@ENTRAPETROL con 1 clic, copio password generado, pego en WhatsApp
- [ ] Puedo resetear password de cualquier cuenta
- [ ] Puedo suspender/reactivar cuenta (cambio `perfiles.estado`)
- [ ] Puedo eliminar cuenta (hard delete con doble confirmación)
- [ ] Gate: solo `logxie_staff` puede invocar la Edge Function (validado via JWT)
- [ ] Con cuenta nueva, login en mi-netfleet funciona y RLS aísla correctamente

**Prompt para copiar al chat**:
```
Lee CLAUDE.md + docs/CONTEXTO_OPERATIVO.md obligatorios (si tocás schema,
también docs/ARQUITECTURA.md).

OBJETIVO: completar el sub-tab 👥 Usuarios en el workspace 🏢 Catálogo de
control.html (hoy es placeholder). Yo (staff) debo poder crear, resetear,
suspender y eliminar cuentas de transportadoras y staff desde control.html
— sin salir del producto ni ir al Dashboard de Supabase.

QUÉ EXISTE HOY (no re-construir):
- Workspace Catálogo en control.html con 2 sub-tabs funcionando (🏭 Clientes,
  🚛 Transportadoras) + sub-tab 👥 Usuarios placeholder (solo texto
  "requiere Edge Function con service_role").
- perfiles.transportadora_id FK + RLS endurecido en viajes_consolidados +
  pedidos (commit 67383c1). Cada cuenta nueva que cree va a nacer aislada.
- Las 7 transportadoras seed en tabla `transportadoras` con email_contacto.
- Helper `is_logxie_staff()` ya existe para gate.

QUÉ FALTA:
1. Edge Function `admin_user` (Deno/TS) en supabase/functions/admin_user/:
   - Gate: validar caller es logxie_staff (via JWT del header Authorization)
   - Acciones: create_user · reset_password · toggle_active · delete_user
   - create_user: admin.auth.admin.createUser() con email_confirm=true,
     handle_new_user crea perfil, después UPDATE perfiles SET tipo,
     estado='aprobado', transportadora_id (si tipo='transportador')
   - reset_password: admin.auth.admin.updateUserById({password})
   - toggle_active: UPDATE perfiles SET estado (aprobado ↔ rechazado)
   - delete_user: admin.auth.admin.deleteUser() (hard delete)
2. Deploy: guiarme step-by-step para `supabase functions deploy admin_user`
   (preguntarme primero si ya tengo Supabase CLI instalado)
3. UI en control.html sub-tab 👥 Usuarios:
   - Tabla con Email · Nombre · Tipo (transportador/staff) · Transportadora ·
     Estado · Últ login · Acciones
   - Modal "+ Nueva cuenta" con radio Tipo (transportador necesita selector
     de transportadora; staff no necesita)
   - Auto-generar password (`Netfleet-` + 6 chars random) mostrado UNA vez
     en toast con botón "Copiar"
   - Por fila: 🔑 Resetear (genera nueva, muestra para copiar) · ⊘ Suspender
     / ↻ Reactivar · 🗑 Eliminar (doble confirm)

ALCANCE: una sesión. Mostrame PLAN con tiempos antes de código. Commits
chicos end-to-end (Edge Function + deploy + UI + test). Si algún paso se
va de tiempo estimado, cerralo bien y lo continuamos en otra sesión.

DECISIONES YA TOMADAS (no volver a discutir):
- Password auto-generado aleatorio mostrado una vez para copiar
- Modal permite crear transportador + staff (radio tipo)
- Eliminar: hard delete con doble confirmación (vs suspender con 1 clic)
- Gate server-side estricto: solo logxie_staff via JWT
- NO magic link por ahora (password-based es más práctico para el caso)

Cuenta test: usar bernardoaristizabal@logxie.com (staff) para probar que
puedo crear nuevas cuentas. Validar aislamiento con una cuenta test nueva.
```

---

### 🎯 Sesión después (B): **Asignar vehículo+conductor al viaje adjudicado** — ~45-60min

**Objetivo**: Bloque 2 del customer journey de la transportadora. En mi-netfleet tab 🚚 Mis viajes, cuando recibe un viaje confirmado, tiene selectores de conductor y vehículo (dropdown de su Flota activa) para asignar quién ejecutará el viaje. Sin retipeo. Sin esto, la Flota existe pero no se usa en la operación real.

**Criterios de done**:
- [ ] En card de viaje adjudicado (mi-netfleet → Mis viajes), hay bloque "Asignación de recursos" al top
- [ ] 2 selects: conductor (activos de mi transportadora) + vehículo (activos)
- [ ] Botón "Asignar" persiste en `viajes_consolidados`: `placa` · `conductor_nombre` · `conductor_id` (UUID del conductor)
- [ ] Si hay docs vencidos del conductor/vehículo elegido, warning suave (no bloquea)
- [ ] CTA destacado "⚠ Asignar antes de cargar" si viaje está confirmado pero sin asignación
- [ ] Post-asignación, timestamps (cargue/descargue) siguen funcionando igual
- [ ] Si flota vacía → link directo al tab 🚛 Flota

**Prompt para copiar al chat**:
```
Lee CLAUDE.md + docs/CONTEXTO_OPERATIVO.md obligatorios. Si tocás schema,
también docs/ARQUITECTURA.md.

OBJETIVO: Bloque 2 del customer journey de la transportadora — asignar
conductor + vehículo al viaje ADJUDICADO, desde mi-netfleet tab "🚚 Mis
viajes". Usa la Flota que ya cargaron en tab 🚛 Flota (commit 49219b7).

QUÉ EXISTE HOY (no re-construir):
- Tablas `conductores` + `vehiculos` con CRUD operativo en mi-netfleet
  tab 🚛 Flota (transportadora_id FK, activo flag, docs).
- Tab 🚚 Mis viajes muestra viajes WHERE proveedor ILIKE empresa + estado
  IN (confirmado, en_ruta, entregado). Card tiene 4 timestamps (llegada/
  salida cargue+descargue) + pedidos con botón cumplido.
- `viajes_consolidados` tiene columnas: placa (text), conductor_nombre
  (text), conductor_id (text — legacy AppSheet id), transportadora_id.
- RLS endurecido: cada transportadora ve solo sus viajes asignados.

QUÉ FALTA:
1. Schema — evaluar si agregar conductor_uuid UUID FK + vehiculo_uuid UUID
   FK a viajes_consolidados (mantener legacy text por compat) o reusar
   conductor_id text. Mi voto: agregar FK nuevos con ON DELETE SET NULL,
   así se mantiene integridad al borrar/desactivar flota.
2. RPC fn_viaje_asignar_recursos(p_viaje_id, p_conductor_id, p_vehiculo_id)
   - Gate: solo la transportadora dueña del viaje
   - Lee nombre del conductor + placa del vehículo
   - Persiste placa + conductor_nombre + conductor_id (uuid) + conductor_uuid
     + vehiculo_uuid
   - Audit acciones_operador
3. UI en mi-netfleet tab Mis viajes:
   - Bloque "Asignación" al top del card (antes de timestamps)
   - Estado: mostrar asignación actual si hay, "⚠ Asignar antes de cargar"
     si vacía
   - 2 <select> con conductores/vehículos activos de la transportadora
   - Warning color-coded si conductor/vehículo tiene docs vencidos (usa
     docsBadgeHTML de flota)
   - Botón "Guardar asignación"
   - Si flota vacía: mensaje con CTA "Ir a Flota para agregar"

ALCANCE: una sesión. Plan con tiempos antes de código. Commits chicos.

DECISIONES YA TOMADAS:
- Asignación NO va en la oferta, va POST-adjudicación (Bernardo 2026-04-22)
- Docs vencidos = warning, NO bloqueo (permite operar, flagea)
- Conductor/vehículo se puede cambiar después de asignado (no es irrevocable)
- Guardar en viajes_consolidados los 5 campos: placa text + conductor_nombre
  text + conductor_id text (legacy) + conductor_uuid FK + vehiculo_uuid FK

Test: logueado como bernardojaristizabal@gmail.com (JR LOGÍSTICA), asignar
Juan Pérez + XYZ789 (la flota que ya cargué en sesión Flota) a uno de los
viajes confirmados de JR (hay 9). Verificar persistencia + que otros viajes
quedan intactos.
```

---

### 🎯 Sesión futura (C): **Resumen ejecutable del viaje + PDF + mapa LogxIA** — ~60min

Al recibir viaje adjudicado, la transportadora tiene card expandible mail-style (clientes, direcciones, horarios, pedidos, contactos) + botón "📄 Generar PDF" (para compartir con conductor) + botón "🗺 Ver mapa sugerido por LogxIA" → abre `analizador-rutas.html?viaje=<id>`. Cierra el **Bloque 3 del journey**.

---

### 🎯 Sesión D — **Empezar implementación LogxIA Fase 1** (piloto: regla #1 auto-swap destino↔dirección) — ~2h

**Objetivo**: arrancar el módulo **LogxIA** como capa de reglas autopilot, dándole contenido ejecutable a los badges 🟢🟡🔴 del panel. Piloto end-to-end: **Regla #1 Auto-swap destino↔dirección** (ROI estimado **80 h/año** — 20% de pedidos nuevos tienen el destino real en la columna `direccion` porque el dropdown del Sheet es cerrado, Bernardo corrige a mano). La infra mínima que se construya con esta regla es reusable para las siguientes.

**Criterios de done**:
- [ ] Diccionario `CIUDADES` centralizado en `netfleet-core.js` (hoy duplicado en 5 HTMLs) + los 5 HTMLs (`index.html`, `transportador.html`, `analizador-rutas.html`, `viaje.html`, `mi-netfleet.html` si aplica) `<script src="netfleet-core.js">` y borran su copia local
- [ ] Tabla `logxia_reglas` (id, codigo, nombre, descripcion, estado `activa|pausada|shadow`, config jsonb, created_at, updated_at) + seed para regla #1
- [ ] Tabla `logxia_acciones` (id, regla_id, entidad_tipo, entidad_id, accion, antes jsonb, despues jsonb, aplicada_at, deshecha_at, deshecha_por) — audit reversible
- [ ] Postgres function `fn_logxia_auto_swap_destino_direccion(p_pedido_id)` — detecta el patrón, hace el swap si es seguro, logea en `logxia_acciones`
- [ ] Trigger `logxia_pedidos_auto_swap` AFTER INSERT/UPDATE OF `destino, direccion` ON `pedidos` que llama la function cuando la regla está `activa` o `shadow`
- [ ] Modo `shadow`: detecta pero NO aplica — solo logea lo que hubiera hecho. Bernardo aprueba pasando de `shadow` a `activa`
- [ ] Botón "Deshacer" en cada fila de `logxia_acciones` por ≥24h (revierte antes↔después)
- [ ] UI en control.html — nuevo workspace `🤖 LogxIA` (icono en nav principal) con 2 sub-tabs:
  - **⚙ Reglas**: lista de reglas con toggle `activa/shadow/pausada` + stats (N aplicadas, N revertidas, % ahorro estimado)
  - **📋 Acciones recientes**: últimas 100 acciones auto con botón deshacer
- [ ] Smoke test E2E: simular 3 pedidos con el bug típico, verificar que se auto-corrigen, verificar deshacer funciona
- [ ] Backfill opcional: correr una vez sobre los pedidos históricos `sin_consolidar + revisado_at IS NULL` para ver cuántos se corregirían hoy

**Decisiones técnicas ya tomadas** (no volver a discutir):
- Arquitectura: **trigger BD** (no job periódico) porque la regla dispara al INSERT/UPDATE de pedido — instantáneo, sin scheduler
- Reversibilidad: toda acción LogxIA tiene botón deshacer por ≥24h (política global del módulo)
- Nivel de confianza: auto-aplicar solo si match es **único y no ambiguo** (destino no en catálogo CIUDADES + dirección tiene exactamente 1 ciudad conocida). Si ambiguo → deja el pedido sin tocar, loguea como "ambiguo — skipped"
- Audit separado: `logxia_acciones` (no reusar `acciones_operador`) para poder filtrar y revertir acciones autopilot sin contaminar el historial de acciones humanas
- Modo `shadow` como default al activar regla por primera vez — Bernardo ve qué haría antes de aprobar

**Prompt para copiar al chat**:
```
Lee CLAUDE.md + docs/CONTEXTO_OPERATIVO.md + docs/LOGXIA_JOURNEY.md
obligatorios. Si tocás schema también docs/ARQUITECTURA.md.

OBJETIVO: arrancar implementación de LOGXIA Fase 1 — capa de reglas
autopilot. Piloto end-to-end con Regla #1: auto-swap destino↔dirección
(80 h/año). Construir infra mínima reusable para reglas futuras.

CONTEXTO DEL BUG (dato calibrador del journey con Bernardo 2026-04-22):
20% de pedidos nuevos tienen el destino canónico mal poblado porque
el vendedor pone el destino real en la columna `direccion` (el
destino del Sheet es un dropdown cerrado que no incluye todos los
municipios de Cundinamarca/Boyacá rural). Bernardo corrige a mano
~2 min por pedido, ~10 pedidos/día → 80 h/año.

PRE-WORK OBLIGATORIO (sin esto la regla no es confiable):
Centralizar diccionario CIUDADES en netfleet-core.js. Hoy está
duplicado en 5 HTMLs: index.html, transportador.html,
analizador-rutas.html, viaje.html, mi-netfleet.html (si tiene).
Cualquier ciudad que falte en un HTML hace que la regla #1 tire
falsos negativos. Unificar primero, después la regla.

QUÉ CONSTRUIR:

BLOQUE 1 — Centralizar CIUDADES (pre-work)
- Mover el dict completo (más el que tiene el analizador post-sesión
  22/04 con +38 municipios Cundinamarca/Boyacá) a netfleet-core.js
- Cada HTML: <script src="netfleet-core.js"></script> antes de su JS
  principal + borrar la copia local
- Verificar: getCoordenadas() sigue funcionando en cada página

BLOQUE 2 — Infra LogxIA (schema + audit)
- Tabla logxia_reglas (id uuid, codigo text UNIQUE, nombre, descripcion,
  estado text CHECK (estado IN ('activa','shadow','pausada')),
  config jsonb, created_at, updated_at) + índice estado
- Tabla logxia_acciones (id uuid, regla_id FK, entidad_tipo text,
  entidad_id uuid, accion text, antes jsonb, despues jsonb,
  aplicada_at timestamptz, deshecha_at timestamptz NULL,
  deshecha_por uuid NULL) + índices regla_id + aplicada_at DESC
- RLS: staff_all en ambas. service_role bypass.
- Seed regla #1:
    INSERT INTO logxia_reglas (codigo, nombre, estado, config) VALUES
    ('r01_auto_swap_destino_direccion',
     'Auto-swap destino↔dirección cuando destino no está en catálogo',
     'shadow', '{"min_confianza":"unico_no_ambiguo"}');

BLOQUE 3 — Lógica de la regla
- Postgres fn fn_logxia_auto_swap_destino_direccion(p_pedido_id uuid):
  1. Lee el pedido (destino, direccion)
  2. Chequea: destino NO matchea ninguna ciudad conocida (catálogo
     hardcoded en la function — mismo dict que netfleet-core.js, o
     leer de tabla ciudades_canonicas si la creamos)
  3. Chequea: direccion contiene EXACTAMENTE 1 ciudad conocida
     (buscar match por palabra, con regex word boundaries)
  4. Si ambas condiciones OK: swap destino↔direccion en el pedido
  5. Si ambiguo o no aplica: skip (loguear como skipped en modo shadow)
  6. Siempre escribe a logxia_acciones (antes/despues, timestamps)
  7. Si regla.estado='shadow': solo loguea, NO aplica el swap
  8. Si regla.estado='activa': aplica el swap + loguea
- Trigger logxia_pedidos_auto_swap AFTER INSERT OR UPDATE OF destino,
  direccion ON pedidos FOR EACH ROW WHEN (estado de regla activa o
  shadow) → llama la fn
- Function auxiliar fn_logxia_deshacer(p_accion_id uuid) — revierte
  una acción si pasaron <24h desde aplicada_at

BLOQUE 4 — UI control.html
- Nuevo workspace 🤖 LogxIA en nav principal (junto a 🏢 Catálogo)
- Sub-tabs:
  * ⚙ Reglas: lista con toggle 3-way (activa/shadow/pausada) +
    stats por regla (N aplicadas 7d, N revertidas, % ahorro estimado)
  * 📋 Acciones: tabla últimas 100 filas de logxia_acciones con
    filtros (por regla, por fecha, solo no-deshechas). Botón "↶
    Deshacer" por fila si aplicada_at dentro de 24h
- RPC calls: fn_logxia_deshacer, UPDATE logxia_reglas.estado

BLOQUE 5 — Test + backfill
- Smoke test E2E: crear 3 pedidos con el patrón (destino bogus,
  dirección con ciudad real), verificar que el trigger en modo
  'shadow' los detecta pero no swapea. Cambiar regla a 'activa',
  correr trigger de nuevo (UPDATE NOOP), verificar swap + audit.
  Deshacer 1. Verificar revertido + marcado deshecha_at.
- Backfill opcional: función fn_logxia_backfill_r01() que corre
  sobre pedidos existentes en estado sin_consolidar. Devuelve count
  de candidatos detectados (sin aplicar — para estimar volumen).

ALCANCE DE LA SESIÓN: 5 bloques en orden. Si se va de tiempo, cerrá
los bloques completos y el resto queda para sesión siguiente.
Obligatorio commit end-to-end por bloque (schema + function + UI +
test). Mostrame PLAN con tiempos antes de código.

Cuenta staff: bernardoaristizabal@logxie.com (logxie_staff).
```

---

### 📌 Notas operativas para todas las sesiones

- **Abrir Claude Code en `D:\NETFLEET`**: CLAUDE.md se carga automáticamente.
- **Primera lectura obligatoria**: `docs/CONTEXTO_OPERATIVO.md` (este archivo) — el TL;DR + secciones de la sesión anterior.
- **Si tocás schema o políticas**: también `docs/ARQUITECTURA.md`.
- **Cuenta test transportadora**: `bernardojaristizabal@gmail.com` / `123ABC` (estado aprobado, transportadora_id=JR LOGÍSTICA).
- **Cuenta staff**: `bernardoaristizabal@logxie.com` (logxie_staff).
- **Timebox**: cada sesión tiene estimado. Si un bloque se va +50% over, cerrá lo verificado y abrí otra sesión para el resto.
- **Commits chicos**: un bloque = un commit end-to-end (schema + UI + test + docs). No acumular 1000+ líneas en un solo push.

---

>
> **Lo nuevo vs. bloque anterior (LogxIA+Ofertantes):** **Overhaul del analizador de rutas** (`analizador-rutas.html`). 18 commits en una sesión extendida atacaron bugs + mejoras de UX reportados por Bernardo al usar el analizador en casos reales. Lo más impactante: **KPIs que reflejan realidad** (duración total cargue→últ entrega, extracostos rojos con viáticos+standby, descargue real sumado), **reprogramación secuencial respetando ventanas** (no más 8 AM para todos), **parser horario AM/PM/M/mediodía + fallback a observaciones**, **pedidos sintéticos + "prestados"** para viajes duplicados con linker imperfecto, **fallback haversine cuando OSRM público satura**, **input búsqueda por RT** en sidebar para histórico. Cada fix con un símtoma concreto de Bernardo. Commits: `ceae39a` → `83bf046`.

## TL;DR de la sesión 2026-04-23 (tarde/noche — analizador-rutas.html overhaul)

### Contexto

Después de cerrar el bloque LogxIA v1 + Ofertantes (commit `ceae39a`), Bernardo pasó a probar el analizador de rutas con un scenario y viaje reales. Detectó 15+ síntomas distintos que colectivamente volvían el análisis poco confiable: horas irreales (12:34 PM cuando cliente cerrado), extracostos subestimados (1 pernocta de $100K para un viaje de 3 días que toma fin de semana), destinos faltantes (18 pedidos → mapa con 7), ventanas no respetadas en reprogramaciones. La sesión se volvió un walkthrough estilo "paso por paso, fix por fix" hasta que el analizador quedó representando la operación real.

### Fixes agrupados por tema

**KPIs realistas (duración, extracostos, descargue)**
- "Conducción 11h7m · sin paradas" reemplazado por **"Duración total 3d 12h · cargue → últ entrega"** — refleja días calendario reales incluyendo pernoctas y fin de semana.
- **Pernoctas reales** = totalDays - 1 (antes contaba solo las visibles en timeline, ahora las implícitas por fin de semana también).
- **Standby** nuevo: días sin entregas entre primero y último a **$500.000/día** (sáb+dom cerrados por clientes Boyacá = $1M extra).
- KPI **"Extracostos"** en rojo reemplaza "Precio publicado" (que era siempre $0 para scenarios). Suma viáticos ($100K/noche × N pernoctas) + standby.
- "10h desc. total" (asumía 60min×10) → **descargue real** sumando `descMin` individual de cada destino.
- Fix división por cero: "+Infinity% vs sheet 0 km" cuando `trip.km=0` (scenario nuevo) → mensaje informativo.

**Reprogramación secuencial que respeta ventanas** — `b1f9c6c`, `60151b7`, `d014c75`
- Antes: destinos saltados (ventana cerrada >1 día) se programaban TODOS a `nextOpenDay 8 AM` sin drive time entre ellos.
- Ahora: **primer reprog a 8 AM + siguientes con drive haversine×1.25 @ 40 km/h + descMin**. Si llegan fuera de horario del cliente (12:34 PM con ventana hasta 12:00) timeline agrega `⏳ Espera hasta 14:00` y posterga la entrega.
- **Día standby visible** entre primer y último día: banner amarillo `📅 Día 3 · domingo · 💤 standby · $500K` (antes se saltaba).
- **Unifica con/sin retorno**: antes `con retorno` usaba código viejo (todos a 8 AM) y `sin retorno` usaba el nuevo. Ahora ambos usan el mismo cálculo secuencial. Return event se mueve al final para sumar drive real desde la últ reprog al origen.
- Fix duplicado reprog cuando hay retorno: `skippedDests.length = 0` después del primer reprogramming, previene que el post-loop duplique.

**Parser horario robusto** — `d014c75`, `1a821ef`
- Antes: `parseHorarioLibre` solo reconocía formatos tipo `8:00-12:00` o `8 a 12`. Default 08:00-17:00 cuando no parseaba.
- Ahora: entiende `AM/PM`, `A.M./P.M.`, `M` (mediodía = 12:00), `"2-4 PM"` con inferencia (si solo end tiene suffix PM y h1<12, aplica PM también a h1).
- **Fallback a `pedido.observaciones`** cuando `pedido.horario` es NULL. Mayoría de pedidos Avgust legacy tienen el horario embebido en texto libre tipo `"RECIBEN DE L-V DE 8:00 A.M A 3:30 P.M"`.
- **Pre-procesa direcciones/teléfonos** para evitar falsos positivos: `"CLL 6 SUR # 10-146 BRR"` antes daba ventana 10:00-14:00 (extraía "10-146"). Ahora se eliminan patrones de calle (CRA/CLL/CALLE/AV/DIAG), numeración (`#`, `Nº`), teléfonos (CEL:, ≥7 dígitos).
- Testeado contra 13 observaciones reales del scenario de Bernardo: **10 parsean correctamente**, 3 requieren segmentación por día (deuda documentada — pendiente).

**Data: viajes incompletos + duplicados** — `d40f2a9`, `462f2bb`, `e2f0308`
- **Pedidos sintéticos** para destinos listados en `v.destino` pero sin pedido linkeado. RT-TOTAL-1775753721851 tenía 12 ciudades en `v.destino` pero solo 7 pedidos linkeados (por linker v3/v4 con rangos/refs raras). Ahora las 12 aparecen en el mapa (las sin pedido con ref `(sin pedido linkeado)` y peso 0).
- **Pedidos "prestados"** vía consecutivos: cuando un viaje tiene duplicado/reconsolidación (`TR REEMPLAZADA` + viaje real con mismos consecutivos), el analizador trae pedidos con sus horarios aunque estén linkeados al otro viaje. Fetch por `pedido_ref IN (tokens de v.consecutivos)` además del `viaje_id`.
- **Input "Buscar por RT"** en sidebar — bypass del fetch limit (100) para consultar cualquier viaje del histórico. ILIKE para match parcial. Ideal para auditar viajes viejos finalizados.
- Fetch default ahora incluye **estado `finalizado`** + limit `100` (antes 50 sin finalizados).

**OSRM saturado → fallback haversine** — `b7b18b4`, `df0ab3e`
- Antes: si OSRM público (router.project-osrm.org) no respondía tras 3 intentos (30s × 3 = 93s), error final "saturado" y analizador bloqueado.
- Ahora: timeout 30s → **10s por intento** (total 33s max). Si los 3 fallan, **fallback haversine × 1.25 @ 30 km/h** con banner amarillo "⚠ OSRM saturado — usando distancia aproximada [Reintentar]". Usuario sigue trabajando con distancias y duraciones aproximadas.

**Otros fixes** — `74672a5`, `402fbdc`, `83bf046`
- Colisión `CC_ZONA_AJUSTE` al centralizar en `netfleet-core.js`: eliminada declaración local en `analizador-rutas.html`.
- `dateFechaBase` scope fix en `renderResults` (estaba definido solo en `runAnalysis`).
- Scenarios dropdown completo: antes solo mostraba el scenario inicial cuando se deep-linkeaba con `?scenario=<id>`; ahora trae sus pedidos junto con los 100 scenarios restantes en BG fetch.
- **Ediciones manuales marcan `userReorderedFlag=true`**: antes `togglePrio`, `updateDescMin`, `updateDestWin`, `toggleDay` no seteaban el flag, entonces "Recalcular con tu orden" renderizaba en la fila SUG (arriba) en vez de USR (abajo). Fix + aclaración: priority solo cambia orden visible si rompe la secuencia NN (un destino que ya era #1 por cercanía no se nota al marcarlo como priority).
- Fix bug latente en `updateDestWin`: la 2da ventana usaba `.dw-to-1` como from (mismo campo que from de v1) en vez de `.dw-from-2`.

### Deuda abierta documentada

- **Parser de ventanas sabatinas**: cuando el texto tiene `"L-V 8am-5:30pm. Sábado 8am-11am"` el parser toma las 2 primeras sin distinguir día (v2 = 08:00-11:00 incorrecto). Requiere segmentación por día (sección L-V vs Sábado). Afecta ~1 de cada 10 pedidos con observaciones complejas.
- **Linker v6 — TR REEMPLAZADA**: hay **84 viajes legacy** con `proveedor='TR REEMPLAZADA'` que son placeholders del AppSheet (reemplazados por otro viaje real con mismos consecutivos). El linker v3/v4 a veces asigna pedidos al TR REEMPLAZADA en lugar del real. Fix propuesto (no implementado): Postgres function que re-linkea pedidos de viajes TR REEMPLAZADA a su hermano con proveedor real, integrada al chain `fn_run_linkers`. Bernardo paró para hacer primero audit del analizador.
- **Recalcular en producción**: Bernardo reportó "netfleet no cargo ni viaje ni pedidos" al final de la sesión. Probablemente sesión expirada / Cloudflare aún deployando — sin stack trace. A verificar primera cosa de la próxima sesión.

### 18 commits de la sesión

`ceae39a` LogxIA v1 + panel Ofertantes · `302a82f` docs TL;DR · `74672a5` CC_ZONA_AJUSTE colisión + regla 5 candidatos on-route · `b7b18b4` fallback haversine OSRM · `df0ab3e` scenarios dropdown + timeouts 30→10s · `263b1bb` reprog saltados + div/0 · `60151b7` KPIs realistas (duración, pernoctas, standby, descargue) · `6f34571` dup reprog fix · `b1f9c6c` reprog secuencial + standby visible + unifica retorno · `402fbdc` dateFechaBase scope · `3db0294` retorno en duración · `0546686` Extracostos KPI · `d014c75` ventanas AM/PM + observaciones fallback + finalizado + limit 100 · `1a821ef` parser direcciones + AM/PM heuristic · `e2f0308` input búsqueda por RT · `d40f2a9` pedidos sintéticos · `462f2bb` pedidos "prestados" consecutivos · `83bf046` userReorderedFlag en toggleDay/Prio/DescMin/DestWin + fix ventana 2.

## TL;DR de la sesión 2026-04-23 (tarde — LogxIA v1 + Ofertantes inline)

### Bloque 1 — Panel "Quién ofertó" inline en Viajes (customer journey adjudicación)

- **Motivación**: Bernardo veía el banner verde "1 oferta recibida · mejor \$X" pero al expandir la card la tabla mostraba `—` en la columna transp. Problema doble: (a) bug de datos (ofertas legacy insert desde mi-netfleet no grababa `transportadora_id`), (b) UX — tenía que expandir card para ver ofertas + no había KPIs por transportadora para decidir adjudicación.

- **Fix render** — [control.html](../control.html):
  - Helper `resolverOfertante(o)` con fallback chain: `ofertas.transportadora_id → usuario_id → perfiles.transportadora_id → transportadoras.nombre → perfiles.empresa → email → '—'`. Resuelve bien aunque el insert desde mi-netfleet no haya grabado el FK.
  - Fetch `perfiles?select=id,nombre,email,empresa,transportadora_id` en `recargarTodo` (state.perfiles) para el fallback.
  - Panel `.ofertantes-panel` visible sin expandir (entre head y body). Por card con ofertas muestra: transportadora · precio · Δ vs mejor · KPIs (# viajes · ticket prom · últ viaje) · botón Adjudicar.
  - Helper `kpisOfertante(o)` calcula desde `state.viajes` filtered por `transportadora_id + estado IN (finalizado, entregado)` → count, avg flete, últ fecha. Usa 1145 viajes backfilled post-RLS.
  - Helper `hace(iso)` formato tiempo relativo.
  - Fix defensivo: si hay oferta `aceptada` en el viaje, las activas muestran "ya hay ganador" en vez de botón Adjudicar (previene inconsistencia como RT-TOTAL-1776821879387 donde se insertó oferta post-adjudicación porque Netfleet adjudicó pero el sync del Sheet pisó `estado=pendiente`).

- **Decisión pendiente**: con "ofertas es solo visual hasta migrar asignación de AppSheet a Netfleet" (Bernardo), el botón Adjudicar en Netfleet crea riesgo de inconsistencia. Se deja operativo con fix defensivo. Decisión final (ocultar botón vs confirm reforzado) queda abierta para próxima sesión de audit Viajes.

### Bloque 2 — LogxIA v1 en tab Pedidos (agrupar inteligente)

- **Motivación**: en tab Pedidos, las 3 opciones "Agrupar por" (Ruta/Origen/Destino) usan el texto crudo → las 92 variantes de "PPAL 3PL LA CARBONERA YUMBO / OCCIDENTE ENTREGAS YUMBO / …" se veían como rutas distintas. Bernardo quería que LogxIA aplicara **reglas de consolidación** que él aplica hoy mental: bodegas mismas físicas agrupadas, cross-client BPO, corredores geográficos reales (no zonas administrativas), contenedores separados, umbrales por corredor.

- **4 opciones en el selector ahora**: `Ruta · Origen · Destino · 🤖 LogxIA`.

- **Pre-work: CIUDADES centralizado parcial**. Solo `control.html` ahora incluye `<script src="netfleet-core.js">`. Los otros 4 HTMLs (index, transportador, analizador, viaje) quedan con copia local hasta Sesión D (regla #1 auto-swap). Opción B del path (atajo) para no bloquear LogxIA.

- **`netfleet-core.js` — nuevos exports globales**:
  - `canonizarNodo(texto)` — usa `getCoordenadas` existente + resuelve nombre canónico en mayúsculas sin tildes. Ej: `PPAL 3PL LA CARBONERA YUMBO → YUMBO`. 191 ciudades curadas.
  - `CORREDORES` — map 193 ciudades → 10 corredores: `VALLE · EJE CAFETERO · BOYACA-CUNDINAMARCA · HUILA-TOLIMA · SANTANDERES · LLANOS · SUR · COSTA · ANTIOQUIA · REMOTO`. Key insight: **Villapinzón (Cund) y Tunja (Boy) comparten corredor BOYACA-CUNDINAMARCA** porque la ruta real pasa por ambos. Validado con pares frecuentes del histórico (Tunja-Villapinzón 18x, Armenia-Chinchiná 43x, Pasto-Popayán 29x).
  - `corredorDe(texto)` = `CORREDORES[canonizarNodo(texto).lower()]`.
  - `estimarPrecioRidge(km, kg, paradas, corredor)` — fórmula Ridge portada verbatim desde `transportador.html` (R²=0.919). Con `CC_ZONA_AJUSTE` (14 zonas tradicionales) + mapping `CORREDOR_A_AJUSTE` (10 corredores → zona Ridge). Ej: BOYACA-CUNDINAMARCA usa ajuste 'BOYACA' (+87K, el más caro rural).
  - **Cleanup pre-sesión**: el archivo tenía código legacy de landing (hero cards + FAB toggle). Se trimmeó a solo helpers reutilizables. -1521 líneas.

- **Schema DB** — [db/zonas_umbrales.sql](../db/zonas_umbrales.sql):
  - `zonas_umbrales(zona PK, min_pedidos, min_flete_pct=3, notas, updated_at, updated_by)` — RLS staff-only.
  - Seed: `BOYACA-CUNDINAMARCA=10` · `EJE CAFETERO=5`. Umbrales restantes se completan iterativamente conforme Bernardo los defina.
  - Carga a `state.zonasUmbrales` + `state.zonasUmbralesMap` en `recargarTodo` para lookup O(1) en el render.

- **UI — `control.html` tab Pedidos en modo 🤖 LogxIA**:
  - **Regla 0 — banda separada**: pedidos con `contenedores > 0` (100% Buenaventura, discriminador perfecto validado con DB: 101 con contenedores + 3756 sin) → banda arriba "📦 Vehículo completo — se ofertan solos". No consolidables.
  - **Regla 1 — canonización**: `keyFor` usa `canonizarNodo(origen) → YUMBO`, `corredorDe(destino) → EJE CAFETERO`. Las 92 variantes de YUMBO → 1 grupo. `FUNZA → BOYACA-CUNDINAMARCA` mezcla 8 pedidos AVGUST (Boyacá) + 2 FATECO (Cundinamarca) cross-client.
  - **Regla 2 — cross-client BPO**: implícito en la canonización. AVGUST + FATECO mezclan naturalmente si comparten `(origen_canon, corredor)`. No hace falta lookup de `plan_bpo` en esta v1 — el grouping funciona para cualquier cliente cuyo nombre de bodega mapee a ciudad canónica.
  - **Regla 3 — umbrales por corredor**: hint verde si `N pedidos listos ≥ zonas_umbrales.min_pedidos` (señal A) OR `peso ≥ 4.000kg` (señal B). Amarillo si falta cerca. Gris si lejos.
  - **Ruta ordenada** en label del grupo — `rutaOrdenada(origenCanon, pedidos)`: destinos únicos canonicalizados sorted by haversine desde origen. Max 5 visibles + "+N más". Ej: `YUMBO → ESPINAL → FUNZA → TUNJA`.
  - **Stats Ridge por grupo** — línea secundaria con `estimarFleteGrupo(origenCanon, corredor, pedidos)`: `flete ≈ $X · N km (~línea) · P paradas · $/kg · $/km · %flete-valor` (rojo si >3%). Km usa haversine al destino más lejano × factor 1.25 (aprox ruta real vs línea recta).
  - **Selección de grupo**: `toggleGrupo` extendido para matchear por `(canonizarNodo(origen), corredorDe(destino))` en modo logxia + banda especial `__LOGXIA_CONTENEDORES__`. Permite seleccionar todo el grupo de una (antes había que hacerlo 1x1 en logxia mode).

- **E2E verificado**: 8 tests de `canonizarNodo` + 13 tests de `corredorDe` (TUNJA, VILLAPINZON, CARTAGO, ARMENIA, PASTO, MEDELLIN, ESPINAL, YUMBO, FUNZA, VILLAVICENCIO, BUCARAMANGA) + test de Ridge (Yumbo→Eje 5000kg 200km = \$1.568K / \$314/kg / \$7.840/km) + test toggle grupo. Todos PASS.

- **Pendientes del módulo LogxIA**:
  - Regla 5 (parada intermedia): detectar pedidos on-route (ej. Villapinzón en ruta Funza→Tunja) y flaguearlos como "candidato parada".
  - Regla 6 (hub routing): Yumbo→Boyacá via Funza (marcar el hub intermedio).
  - Persistir sugerencias a tabla `logxia_sugerencias` para learning loop Fase 1 (dashboard precisión: "LogxIA sugirió N consolidaciones, aceptaste M — ajustar umbral Y → X").
  - Completar umbrales de los 8 corredores restantes conforme Bernardo los defina.
  - Agregar ancho de UI para la 2da línea de stats Ridge (actualmente comprime en groupe-row-inner — revisar CSS).

>
> **Lo de la sesión anterior (Catálogo Usuarios):** **Sub-tab 👥 Usuarios operativo en Catálogo** — Bernardo ya puede crear/resetear/suspender/eliminar cuentas de transportadoras + staff desde `control.html` → 🏢 Catálogo → 👥 Usuarios. Edge Function `admin_user` deployada (5 acciones · service_role + gate `logxie_staff` via JWT · log a `acciones_operador`). Campo nuevo `perfiles.rol_transportadora` enum `comercial|operativo|facturacion` — informativo hoy, preparado para gate de tabs en mi-netfleet en sesión futura. Password auto-generado `Netfleet-XXXXXX` con botón "📱 Copiar para WhatsApp" que arma mensaje completo con link + email + pass. Onboarding listo: crear transportadora en Catálogo → crear N usuarios linkeados (uno por rol) → mandar credenciales por WhatsApp.

## TL;DR de la sesión 2026-04-23 (Catálogo · Usuarios)

### Bloque Usuarios — onboarding end-to-end desde control.html

- **Motivación**: cerrar bloqueo de onboarding. Para compartir `netfleet.app/mi-netfleet` con las 7 transportadoras por WhatsApp con credenciales, hace falta poder crear cuentas sin ir al Dashboard de Supabase. Con RLS ya endurecido (sesión anterior), cada cuenta nueva nace aislada correctamente.

- **Schema** — [db/modulo4_usuarios_admin.sql](../db/modulo4_usuarios_admin.sql) + [db/perfiles_rol_transportadora.sql](../db/perfiles_rol_transportadora.sql):
  - `perfiles.rol_transportadora TEXT` CHECK IN `('comercial','operativo','facturacion')`. Nullable (solo aplica cuando `tipo=transportador`). Hoy **solo informativo** — no gate de acceso. Preparado para cuando se quiera restringir tabs en mi-netfleet por rol.
  - `acciones_operador.accion` CHECK extendido con 4 acciones: `usuario_crear`, `usuario_reset_password`, `usuario_toggle_active`, `usuario_eliminar`.
  - `acciones_operador.entidad_tipo` CHECK extendido con `usuario`.
  - Índice parcial `idx_perfiles_rol_transportadora` donde NOT NULL.

- **Edge Function `admin_user`** — [supabase/functions/admin_user/index.ts](../supabase/functions/admin_user/index.ts):
  - Runtime Deno (`@supabase/supabase-js@2` — SDK v2 latest, necesario para soporte ES256).
  - Deploy con `--no-verify-jwt` — el gateway de Supabase NO soporta verificar JWTs ES256 (el nuevo formato asimétrico) en su capa `verify_jwt`. Error exacto: `UNAUTHORIZED_UNSUPPORTED_TOKEN_ALGORITHM`. Workaround: disable verify_jwt + validar manualmente en el código con `admin.auth.getUser(token)` usando `service_role` key (que SÍ soporta ES256).
  - Gate server-side: (1) Bearer header presente → (2) `admin.auth.getUser(token)` decodifica JWT y resuelve user → (3) chequeo `perfiles.tipo='logxie_staff'` + `estado='aprobado'`. Si cualquier paso falla → 401/403.
  - 6 acciones: `list_users`, `create_user`, `reset_password`, `toggle_active`, `delete_user`, `update_rol` (cambio inline de rol desde la tabla).
  - Password auto-generado `Netfleet-XXXXXX` con chars sin ambiguedad (sin 0/O/1/l/I) usando `crypto.getRandomValues`.
  - Audit log: cada acción escribe a `acciones_operador` con snapshot en metadata.
  - README de deploy + curl smoke tests en [supabase/functions/admin_user/README.md](../supabase/functions/admin_user/README.md).

- **UI** — [control.html](../control.html):
  - Sub-tab 👥 Usuarios en Catálogo (reemplaza el placeholder "Módulo en construcción").
  - Filtros: search box · radios tipo (Todos/Transportador/Staff) · checkbox "Mostrar suspendidos".
  - Tabla: Email · Nombre · Tipo (badge color-coded) · Transportadora · **Rol (select inline — cambia en caliente via `update_rol`)** · Estado · Últ login · Acciones (🔑 reset · ⊘/↻ toggle · 🗑 delete con doble confirm).
  - Modal "Nueva cuenta": radio tipo · selector transportadora (lazy-load si state vacío, con fallback fetch directo) · selector rol · email/nombre/teléfono.
  - Modal "Password generado": se muestra email + password UNA sola vez · 2 botones copy ("📱 Copiar para WhatsApp" arma mensaje completo con link + email + pass, "📋 Copiar solo contraseña").
  - Contador `👥 Usuarios N` en sub-nav, filtra suspendidos.

- **Proceso de deploy** — aprendizaje operativo:
  - Ni Node/npm ni Supabase CLI están instalados en el sistema de Bernardo. Tampoco Docker (warning esperado del CLI, no bloquea deploy cloud).
  - CLI binario Windows (~30MB tar.gz, ~94MB ejecutable) descargado de github releases a `/tmp/sbcli` temporal, borrado post-deploy.
  - Personal Access Token (PAT) de Bernardo vía env var `SUPABASE_ACCESS_TOKEN`. Tras el deploy, Bernardo revocó el PAT inmediato. Documentado para futuro: para deploys siguientes de Edge Functions, repetir el flow (descargar CLI binario temp + PAT temp + revocar).

- **Gotcha importante — JWT ES256**: Supabase migró sus JWTs de HS256 a ES256 (asymmetric ECDSA). El gateway de Supabase y versiones viejas del SDK `supabase-js` (<2.45) no soportan verificar ES256. Síntomas: `{"code":"UNAUTHORIZED_UNSUPPORTED_TOKEN_ALGORITHM","message":"Unsupported JWT algorithm ES256"}`. Fix: (1) SDK import `@supabase/supabase-js@2` (latest) en la Edge Function, (2) deploy con `--no-verify-jwt`, (3) validar token manualmente con `admin.auth.getUser(token)` que usa service_role.

- **E2E test PASS**: crear cuenta transportador con rol → verificar linkeo a transportadora correcto → cambiar rol inline → reset password → suspender → reactivar → eliminar con doble confirmación. Todo loggeado en `acciones_operador`.

- **Archivos creados/modificados**:
  - ✅ Nuevos: `db/modulo4_usuarios_admin.sql`, `db/perfiles_rol_transportadora.sql`, `supabase/functions/admin_user/index.ts`, `supabase/functions/admin_user/README.md`
  - ✅ Modificado: `control.html` (sub-tab HTML + 2 modales + ~280 líneas JS: `renderUsuarios` · `cargarUsuarios` · `callAdminUser` · `abrirUsuarioModal` · `crearUsuario` · `mostrarPassGenerado` · `copiarPassWhatsApp` · `resetearPassword` · `toggleActivoUsuario` · `eliminarUsuario` · `cambiarRolUsuario` · `onUsrTipoChange`)

- **Próximo paso (Bloque 2)**: asignar vehículo+conductor al viaje adjudicado desde mi-netfleet → tab "Mis viajes". Ver sección "Próximas sesiones" arriba.

>
> **Lo nuevo vs. bloque anterior (Flota):** **RLS endurecido** en `viajes_consolidados` + `pedidos` — cada transportadora ahora ve SOLO sus viajes (los asignados a ella + subastas abiertas + invitaciones activas). Antes `authenticated_all` dejaba a cualquier transportador logueado hacer `fetch('/rest/v1/viajes_consolidados')` y ver TODOS los viajes con flete/proveedor/valor de la competencia + pedidos con cliente final, dirección, teléfono. Backfill de 1145 viajes legacy (7 transportadoras seed) via substring match. Test end-to-end PASS con JWT auth: staff ve 1311, JR user ve 236 (todos suyos, 0 ajenos).

## TL;DR de la sesión 2026-04-22 (noche — RLS aislamiento)

### Bloque RLS endurecido — cerrar fuga antes del onboarding

- **Motivación**: preparando onboarding de las 7 transportadoras (dar credenciales + link `netfleet.app/mi-netfleet`), descubrí que `viajes_consolidados` y `pedidos` tenían policy `authenticated_all` (`USING (true) WITH CHECK (true)`). Cualquier transportador logueado hacía DevTools → Network → fetch raw → veía competencia completa. UI filtraba pero DB no. Bloqueante para "cada una ve lo suyo".
- **Demostración del gap (antes del fix)**: logueado como JR, un simple `fetch('/rest/v1/viajes_consolidados')` devolvía:
  - ENTRAPETROL: $1.370.000 en Funza→Villavicencio (valor mercancía $99.8M)
  - TRASAMER: $1.170.000 en Funza→Montería
  - TRANSPORTE NUEVA COLOMBIA: $1.250.000 en Yumbo→Espinal
  - 1300+ pedidos con cliente final, bodega, teléfono, valor
- **Backfill** — pre-requisito crítico: 1300 viajes legacy (`sheet_asignados` source) tienen `proveedor` texto pero `transportadora_id=NULL`. Si ponés RLS `transportadora_id = _mi_transportadora_id()` sin backfill, JR no ve sus 236 viajes históricos.
  - Mapping explícito por substring upper (conservador) de 7 seed:
    | Patrón LIKE | Seed |
    |---|---|
    | `%ENTRAPETROL%` | ENTRAPETROL → 359 viajes |
    | `%LOGISTICA Y SERVICIOS JR%` / `%JR LOGIS%` | JR LOGÍSTICA → 236 |
    | `%TRASAMER%` | TRASAMER → 180 |
    | `%NUEVA COLOMBIA%` | TRANS NUEVA COLOMBIA → 171 |
    | `%PRACARGO%` | PRACARGO → 137 |
    | `%GLOBAL LOG%` | GLOBAL LOGÍSTICA → 41 |
    | `%VIGIA%` / `%VIGÍA%` | VIGÍA → 21 |
  - Cobertura: **1145 / 1300 viajes con FK (88.1%)**. Los 155 restantes: 84 "TR REEMPLAZADA" (placeholder legacy) + 71 de 9 transportadoras no-seed que no tienen fila en `transportadoras` (AGROMARK, MULTITRANS VVL, AGROEXPRESS, etc.). Esos quedan solo visibles para staff — es correcto, no tienen cuenta de usuario.
- **Policies nuevas** en [db/modulo4_rls_aislamiento.sql](../db/modulo4_rls_aislamiento.sql):
  - `viajes_consolidados`:
    - DROP `authenticated_all`
    - `viajes_staff_all` (ALL) — `is_logxie_staff()`
    - `viajes_transp_ver_propios` (SELECT) — `transportadora_id = _mi_transportadora_id()`
    - `viajes_transp_ver_subasta` (SELECT) — `estado=pendiente AND proveedor IS NULL AND subasta_tipo='abierta' AND publicado_at IS NOT NULL`
    - `viajes_transp_ver_invitados` (SELECT) — `id IN (SELECT viaje_id FROM invitaciones_subasta WHERE transportadora_id = _mi_transportadora_id())`
    - Se mantienen intactos: `anon_select_publicos` (landing pública) + `service_role_all`
  - `pedidos`:
    - DROP `authenticated_all`
    - `pedidos_staff_all` (ALL) — `is_logxie_staff()`
    - `pedidos_transp_ver_propios` (SELECT) — `viaje_id IN (SELECT id FROM viajes_consolidados WHERE transportadora_id = _mi_transportadora_id())`
  - Detalle sensible (cliente final, dirección, tel, valor_mercancia) NUNCA expuesto antes de ganar la subasta.
- **Test end-to-end PASS** (JWT claims emulados bajo `SET ROLE authenticated`):
  - **Staff** `fa822bae-…` (Bernardo logxie): `is_logxie_staff()=true`, viajes_consolidados 1311, pedidos 3839 ✓
  - **Transportador JR** `e2269e48-…`: `is_logxie_staff()=false`, `_mi_transportadora_id()=JR`, viajes visibles 236 (todos suyos, 0 ajenos), pedidos 785 (todos de sus 236 viajes)
- **Prereqs verificados**: `fn_adjudicar_oferta` y `fn_asignar_transportadora_directo` ya setean `viajes_consolidados.transportadora_id` (viajes nuevos post-adjudicación quedan visibles al ganador). `fn_reabrir_viaje` lo pone a NULL correctamente.
- **Próximo bloque**: sub-tab 👥 Usuarios en Catálogo (control.html) — Edge Function + UI para que Bernardo cree/resetee/desactive cuentas de transportadoras desde el panel. Con RLS ya endurecido, las cuentas nuevas son seguras desde el momento 0.
>
> **Lo nuevo vs. cierre anterior:** **Módulo 4 Flota** — tab 🚛 Flota en mi-netfleet deja de ser placeholder. Schema `conductores` + `vehiculos` + `documentos_flota` (polimórfico) + bucket Storage privado `flota-docs` + 6 Postgres fns CRUD + RLS por transportadora. UI completa en mi-netfleet.html con 2 sub-tabs, CRUD inline, modal de docs con upload + color-coded estado vencimiento (🟢/🟡/🔴/⚪). `perfiles.transportadora_id FK` nuevo + test user linkeado a JR LOGÍSTICA. Smoke test end-to-end PASS: crear conductor, crear vehículo, subir doc con vence_at, verificar Storage + DB + audit trail.

## TL;DR de la sesión 2026-04-22 (noche — Flota)

### Bloque 1 completo — Schema + UI Flota end-to-end

- **Motivación (customer journey)**: para cerrar el loop de bidding, los conductores y vehículos tienen que estar **precargados una sola vez**. Al adjudicar un viaje, la transportadora elige de dropdown — sin retipeo. La asignación vehículo/conductor NO va en la oferta (decisión de Bernardo: fiel a cómo opera hoy, a veces el conductor se define último momento), va en el seguimiento post-adjudicación (Bloque 2 siguiente).
- **Schema** — [db/modulo4_flota.sql](../db/modulo4_flota.sql):
  - 3 tablas nuevas: `conductores` (14 cols, FK transp, UNIQUE cedula por transp), `vehiculos` (14 cols, FK transp, placa upper auto, UNIQUE placa por transp), `documentos_flota` (polimórfico, UNIQUE entidad_tipo+entidad_id+tipo_doc → 1 doc vigente por tipo).
  - 6 Postgres fns SECURITY DEFINER: `fn_flota_conductor_upsert/desactivar`, `fn_flota_vehiculo_upsert/desactivar`, `fn_flota_doc_upsert/eliminar`. Todas con gate `is_logxie_staff() OR transp_own`, todas escriben audit a `acciones_operador`.
  - Helper `_mi_transportadora_id()` resuelve via `perfiles.transportadora_id` (FK nuevo) con fallback string-match `perfiles.empresa ↔ transportadoras.nombre`. Evita romper cuentas legacy que tienen empresa pero no FK.
  - Bucket Storage `flota-docs` privado. Path: `{transp_id}/{entidad_tipo}/{entidad_id}/{tipo_doc}_{ts}.{ext}`. RLS Storage: `(storage.foldername(name))[1]::uuid = _mi_transportadora_id()`.
  - RLS por tabla: staff_all + transp_own + service_role. 14 policies totales (9 tablas + 5 storage).
  - Acciones `flota_*` (8 nuevas) + entidad_tipo `conductor`/`vehiculo`/`doc_flota` agregados al CHECK de `acciones_operador`.
  - ALTER `perfiles` ADD `transportadora_id UUID` FK + populate de `bernardojaristizabal@gmail.com` → JR LOGÍSTICA.
- **UI mi-netfleet** — [mi-netfleet.html](../mi-netfleet.html):
  - Tab 🚛 Flota: 2 sub-tabs (👷 Conductores N · 🚛 Vehículos M) con CRUD inline.
  - Cards por entidad con `.fitem`: nombre + especs + docs badge (🟢 al día · 🟡 N por vencer · 🔴 N vencidos · ⚪ N faltan) + botón "Gestionar" docs + editar / desactivar.
  - Modales: alta/edición conductor (7 campos), alta/edición vehículo (7 campos), docs por entidad (modal wide con `.doc-row` grid).
  - Docs conductor (7 tipos): cédula · licencia (+ vence + categoría) · EPS · ARL · examen médico · sust.peligrosas (opcional, agroquímicos) · hoja de vida (opcional).
  - Docs vehículo (5 tipos): tarjeta propiedad · SOAT · tecnomecánica · póliza RC · foto (opcional).
  - Estado por doc color-coded por `vence_at`: >30d 🟢 / 0-30d 🟡 / vencido 🔴 / sin vence 🟢✓.
  - Upload a Storage directo via REST (`POST /storage/v1/object/flota-docs/<path>` con `x-upsert: true`), luego llama `fn_flota_doc_upsert` con `archivo_url` = path. Ver docs via signed URL con `POST /storage/v1/object/sign/flota-docs/<path>`.
- **Smoke test end-to-end PASS** (cuenta `bernardojaristizabal@gmail.com` / 123ABC, cargo flota en JR LOGÍSTICA):
  - Conductor "Juan Pérez Ramírez" CC 1234567890 Lic C2 ✓
  - Vehículo "XYZ789" Tractomula Kenworth 2020 32.000 kg ✓
  - Doc licencia PDF fake subido con `vence_at = hoy+6m` → badge 🟢 182d en modal, card muestra "⚪ 4 faltan" (5 obligatorios - 1 subido)
  - Storage object persistido (23 bytes), path correcto
  - Audit trail: 3 entries (`flota_conductor_crear`, `flota_vehiculo_crear`, `flota_doc_subir`)
- **Próximo paso (Bloque 2)**: asignar vehículo+conductor al viaje adjudicado desde tab "Mis viajes" — selects + persiste en `viajes_consolidados.placa/conductor_nombre/conductor_id`. Estimación ~45min. Ver journey plan en el mensaje de este chat.
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
- **Tab 🚛 Flota** — ✅ ACTIVO (2026-04-22 noche). 2 sub-tabs Conductores/Vehículos con CRUD inline, modal docs con upload + color-coded vence. Ver TL;DR arriba + [db/modulo4_flota.sql](../db/modulo4_flota.sql).
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
