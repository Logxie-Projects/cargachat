# LOGXIA — Journey operativo + reglas autopilot

> Fuente de verdad del **qué hace Bernardo hoy, qué empieza a hacer LogxIA en cada fase, y en qué orden lo construimos.** Esta es la spec de reglas de autopilot que alimenta los tiles 🟢🟡🔴 del panel de control.
>
> Última revisión: 2026-04-22 (sesión journey mapping).

---

## 🚀 Próxima regla a implementar — Fase 1 Piloto

**Regla #1: Auto-swap destino↔dirección** · ROI estimado **80 h/año**

**Contexto:** 20% de pedidos nuevos tienen el destino canónico mal poblado porque el vendedor pone el destino real en la columna `direccion` (el destino del Sheet es un dropdown cerrado que no incluye todos los municipios). Bernardo hoy corrige manualmente cada uno. LogxIA puede detectarlo y hacer el swap solo, con log de audit para que se pueda revertir.

**Pre-work (bloquea la regla):**
- Centralizar diccionario `CIUDADES` en `netfleet-core.js` — hoy está duplicado en 5 HTMLs (index, transportador, analizador-rutas, viaje, netfleet-core) — ver deuda técnica en CLAUDE.md.

**Infra mínima LogxIA a construir con esta regla** (reusable para siguientes):
- Tabla `logxia_reglas` (id, nombre, estado activa/pausada, config jsonb, creada_por, created_at)
- Tabla `logxia_acciones` (regla_id, entidad_tipo, entidad_id, accion, antes/después, aplicada_at) — audit separado de `acciones_operador`
- Postgres function o trigger que ejecuta la regla cuando un pedido entra en estado revisable
- UI en control.html (tab Inicio o workspace nuevo) para ver reglas activas + toggle on/off + últimas acciones

**Decisiones técnicas pendientes:**
- Trigger BD (instantáneo) vs job periódico n8n (batch). Para #1 el trigger BD es lo natural.
- Política reversible: toda acción LogxIA debe tener botón "deshacer" por ≥24h.
- Nivel de confianza: solo auto-ejecutar si match es único y no ambiguo. Si ambiguo → 🟡 pre-sugerir, humano aprueba.

**Siguientes candidatas después de #1:**
1. #2 Rating implícito Fase 0 (desbloquea panel comparativo ofertas)
2. #4 Auto-cerrar viajes terminales +Xh
3. #5 Hint "sin ofertas hace Xh → republicar"

---

## TL;DR — filosofía del piloto

Cada tile del panel de control lleva un badge:

- 🟢 **Rutina** — LogxIA lo ejecuta solo según regla clara. Bernardo solo supervisa por excepción.
- 🟡 **Supervisada** — LogxIA propone / pre-clasifica, Bernardo aprueba con 1 clic o corrige.
- 🔴 **Decisión humana** — LogxIA alerta pero no decide. Siempre requiere juicio.

La capa de reglas se construye en 3 fases:

1. **Fase 0 (lo que HOY puede salir con datos que ya tenemos)** — cálculos derivados, hints visuales, sin input humano nuevo.
2. **Fase 1 (reglas ejecutables que quitan trabajo manual)** — 1 clic aprobar, acciones automáticas seguras.
3. **Fase 2 (propuestas con contexto)** — LogxIA sugiere combinaciones optimizadas, Bernardo acepta/modifica.
4. **Fase 3 (autonomía supervisada en rutas recurrentes)** — ciertas decisiones se automatizan 100%, Bernardo ve en dashboard.

---

## Tabla journey — 7 pasos + 3 invisibles

| # | Paso | Tile panel | Badge | HOY (manual) | Fase 1 | Fase 2 | Fase 3 |
|---|---|---|---|---|---|---|---|
| 0 | **Intake** | *(invisible)* | 🟢 | AppSheet→Sheet→Supabase vía `sync_from_csv.py` / n8n cron. Bernardo no toca. | Cron 15min automático activo + webhook manual | Parser email libre (Nivel 1 del Módulo 2) con Claude API | Webhook CRM Avgust directo (Nivel 4) — sin AppSheet |
| 1 | **Revisar** | 📋 Revisar nuevos | 🟡 | ~2 min/pedido. 20% tienen corrección (bug dominante: destino↔dirección swap). Detalles especiales están en campos (horario, tel, etc.) — no es tácito. | **⭐ Auto-swap destino↔dirección** cuando destino no está en catálogo y dirección sí tiene ciudad. Flagea anomalías (peso raro, sin contacto). Detecta duplicados. | Sugiere correcciones ("¿querías MOSQUERA?"). Extrae datos faltantes de observaciones. Pre-clasifica prioridad desde histórico cliente. | Auto-revisa pedidos "obviamente OK" del mismo patrón. Solo te pasa los raros. |
| 2 | **Consolidar** | 📦 Listos para consolidar | 🟢 | Busca patrones de ruta, llena vehículo, despacha cuando es rentable. Rentabilidad AVGUST → calculadora Ridge ya la resuelve. Juicio real = "¿espero o despacho?" | Panel muestra sub-split por zona dentro de cada origen (✅ hecho 2026-04-22). Capa **scenarios** permite armar N combinaciones tentativas sin consumir pedidos (✅). Analizador-rutas en el mismo modal (✅). | Predicción de flujo: "si esperás 24h hay N% de chance de +M pedidos en esta ruta" (modelo series de tiempo con 3.748+ pedidos históricos). Propuesta diaria: "4 viajes listos para hoy, 2 esperando más". | Rutas recurrentes (ej. Funza→Cali semanal) se auto-consolidan y publican solo. Bernardo ve en dashboard. |
| 2b | **Hub / depot intermedio** | — (futuro tile) | 🟡 | Tácito — Bernardo sabe "Yumbo despacha Pasto". | — | *"💡 Este pedido Pasto podría ir vía Yumbo — últimos 60 días salieron 18 viajes Yumbo→Pasto."* Modelar entidad `hubs`. | Auto-propone depot intermedio con costo/ahorro calculado. |
| 3 | **Publicar** | ✏️ Borradores + 🤝 Publicados | 🟡/🟢 | Subasta por default (broadcast + price discovery). Directo solo si: ruta dominada + buen precio + rapidez + seguridad. Re-subasta manual si no hay ofertas. | Hint "sin ofertas hace Xh → republicar". Memoria "ruta dominada por X" ("últimos 10 Funza→Cali: 8 VIGÍA avg $X"). Sugerir modo (abierta/cerrada/invitar set). | Auto-republicar tras Nh de silencio. Auto-invitar al set probable según ruta+zona. | Ruta+proveedor recurrente → publica directo sin subasta, con precio de mercado implícito. |
| 4 | **Adjudicar** | 💰 Con ofertas (en Publicados) | 🟢 | (No existe UI real hoy — Form legacy). Necesita **panel comparativo**. | Panel comparativo: precio vs Ridge (delta color) · horario vs ventana · rating transportadora · histórico ruta (N viajes, % on-time) · zona (experiencia). | LogxIA sugiere: *"Adjudicar a X: 3% bajo Ridge, rating 4.7, 12 viajes en zona sin novedad, respondió primero"* — vos 1-clic adjudicás o rechazás. Aprende de tus decisiones. | Auto-adjudica al proveedor top-ranked de la ruta si oferta está en rango +/-X% del Ridge. Alerta sólo si excepciones. |
| 4b | **Rating** (pre-work) | — | — | No existe hoy. | **⭐ Fase 0 implícito**: calcular rating desde % on-time, % entregado_ok, % cumplidos a tiempo, N viajes — sin input manual. | Widget rating al cerrar viaje (3 actores: Logxie + cliente BPO + destinatario; 6 dimensiones). Mixto 40% implícito + 60% explícito con decay temporal. | Rating se auto-actualiza con cada viaje. |
| 5 | **Notificar + ejecutar** | 📍 Esperando cargue + 🚛 En ruta | 🟢 | Post-adjudicación: mail manual / coordinador WhatsApp. Tiempos cargue/ruta manuales (= señal de demoras bodega, feature no bug). | Mail auto al adjudicar. **ETA por pedido (analizador-rutas) visible en card de viaje activo** (✅ hecho 2026-04-22 — analizador Supabase). Alerta si `salida_cargue` no llega Xh después de acordada. "Demora bodega promedio" por cliente/zona (input rating implícito). | Mail + acuse recibo proveedor. Auto-alerta WhatsApp si cargue tarda >threshold. Re-estimación ETA dinámica si salida_cargue se corre. | Auto-notifica WhatsApp al proveedor + al destinatario ("tu pedido pasa mañana AM por la zona"). |
| 6 | **Entregar + cerrar** | 📬 Listos cerrar + ⚠️ Novedad | 🟢/🔴 | Intentos hasta 3 (`intentos_entrega`). Cumplidos (foto/PDF) vía AppSheet → Drive → enlazado en control.html (✅). Cerrar viaje manual cuando todos los pedidos son terminales. | **Auto-cerrar** cuando 100% pedidos en estado terminal y pasaron Xh. Widget rating (3 actores) se abre al cerrar. Hint "2 cumplidos faltan" si intento=entregado pero sin foto/PDF. Alerta 🔴 novedad con sugerencia contextual ("este cliente ya tuvo N rechazos"). | Auto-cerrar sin confirmación en rutas recurrentes con historial limpio. Triage automático de novedades (escalar vs archivar). | Novedad recurrente del mismo cliente → alerta proactiva al equipo comercial con contexto de LogxIA. |
| 7 | **Facturar + cobrar** | *(no existe tile)* | — | Proveedor factura offline tras cumplidos. Cliente paga sin visibilidad digital. Reportes ad-hoc. | **Módulo 6 nuevo (spec abajo)**: tab "Facturar" en mi-netfleet (gate cumplidos 100%). Portal cliente.html para Avgust (ve cumplidos + facturas). | Portal Avgust aprueba/paga 1-clic. Conciliación automática factura vs precio adjudicado. Alertas "factura aprobada esperando pago >Nd". | Pre-factura automática emitida por Logxie al cliente con desglose + anexos; proveedor solo sube fiscal. |

---

## ⭐ Reglas Fase 1 priorizadas (implementación)

Orden por ROI (ahorro × facilidad). Las ⭐ son las de mayor impacto inmediato.

| # | Regla | Ahorro estimado | Dificultad | Estado | Pre-work |
|---|---|---|---|---|---|
| 1 | ⭐ **Auto-swap destino↔dirección** cuando destino no en catálogo y dirección sí tiene ciudad | **~80 h/año** (50 pedidos/día × 20% × 2 min) | 🟢 Fácil | 🔲 pendiente | Catálogo ciudades centralizado (hoy duplicado en 5 HTMLs — deuda técnica) |
| 2 | ⭐ **Rating implícito Fase 0** (calcular desde datos existentes sin input humano) | Desbloquea #3 | 🟢 Fácil | 🔲 pendiente | Asegurar timestamps de `intentos_entrega` + `cumplidos` con `subido_at` |
| 3 | **Panel comparativo ofertas** en control.html | Decisión más rápida + mejor elección | 🟡 Medio | 🔲 pendiente | (a) ofertas reales = Apps Script mail → Netfleet + onboarding transportadoras; (b) Regla #2 rating implícito |
| 4 | **Auto-cerrar viajes 100% terminales +Xh** | ~5 min/día | 🟢 Fácil | 🔲 pendiente | Validar edge case `cancelado_cliente` y otros no-cerrables |
| 5 | **Hint "sin ofertas hace Xh → republicar"** en tile Publicados | Reduce ciclos manuales | 🟢 Fácil | 🔲 pendiente | Usa `publicado_at` ya existente |
| 6 | ~~ETA analizador-rutas embebido en control.html~~ → **analizador Supabase**  | Decisión en contexto | 🟡 Medio | ✅ hecho 2026-04-22 | — |
| 7 | **Scenarios** — capa tentativa de consolidación | Sin scenarios, los pedidos desaparecen al armar combinaciones alternativas | 🟡 Medio | ✅ hecho 2026-04-22 | — |
| 8 | **Badge zona inline + sub-split por zona en modo Origen** | Elimina filtrado mental de "estos 3 van, estos 2 no" | 🟢 Bajo | ✅ hecho 2026-04-22 | — |
| 9 | **Hint "si esperás 24h +M pedidos"** en Consolidar | Mejor timing consolidación | 🔴 Difícil | 🔲 diferido a Fase 1.5/2 | Modelo de series de tiempo con `viajes_consolidados` histórico |
| 10 | **Widget rating explícito al cerrar viaje** | Completa el loop Uber-like | 🟡 Medio | 🔲 pendiente | Regla #2 (Fase 0) primero; UI modal con 6 dimensiones × 3 actores |

---

## ⚠️ Supuestos críticos / pre-work por regla

1. **Regla #1 (auto-swap)** — catálogo de ciudades canónico. Hoy el diccionario `CIUDADES` está duplicado en 5 HTMLs (deuda técnica documentada en CLAUDE.md). Centralizar en `netfleet-core.js` primero.

2. **Regla #2 (rating implícito)** — requiere:
   - `intentos_entrega.timestamp` (ya existe)
   - `pedidos.cumplido_subido_at` (NO existe — hoy solo hay filename→Drive lookup). Agregar trigger que capture `subido_at` cuando el sync escribe cumplido_foto_url.
   - Vista SQL `v_rating_implicito_proveedor` que agregue las métricas por transportadora.

3. **Regla #3 (panel comparativo)** — requiere:
   - **Ofertas reales en Supabase** → pre-requisito: B (Apps Script mail → Netfleet link) + onboarding 7 transportadoras (pre-crear cuentas staff + mandar credenciales por WhatsApp).
   - Regla #2 rating implícito activa.

4. **Regla #4 (auto-cerrar)** — validar que NO haya estados terminales que requieran confirmación (ej. `cancelado_cliente`, `devuelto_bodega` con reclamo pendiente). Fase 1 conservadora: solo auto-cerrar cuando `100% entregado_ok + cumplidos subidos + 24h`.

5. **Regla #9 (predicción timing)** — requiere volumen histórico por ruta × cliente. 3.748 pedidos alcanza para rutas frecuentes (Funza→Cali, Yumbo→Pasto), insuficiente para rutas raras. Modelar con intervalos de confianza.

6. **Módulo 6 Facturación** — decisión de storage (Supabase Storage vs Drive), diseño del portal cliente (`cliente.html`), flujo de aprobación.

---

## 🎭 Sistema de calificación (spec Fase 1)

Decidido con Bernardo 2026-04-22.

**Actores que califican** (3):
1. Logxie staff (Bernardo + futuro staff)
2. Cliente BPO (Avgust, vía link por mail al cerrar viaje)
3. Destinatario del pedido (bodega cliente final, 1-5 rápido)

**Momento**: al cerrar viaje (1 vez).

**6 dimensiones**:
- Puntualidad cargue (hora llegada vs acordada)
- Puntualidad descargue (hora llegada vs ventana)
- Comunicación WhatsApp (responden, avisan retrasos)
- Cumplido correcto (foto + PDF subidos a tiempo)
- Trato al cliente final (percepción bodega)
- Global 1-5 (impresión general)

**Visibilidad**:
- Transportadora ve la propia agregada + comparativa anónima ("top 3 en tu zona")
- Otros transportadores: ranking anónimo por zona/ruta

**Fase 0 (hoy con datos existentes)** — calcular rating implícito desde:
- % on-time (salida_cargue vs fecha_cargue acordada)
- % entregado_ok vs entregado_novedad vs rechazado
- % pedidos con foto + PDF subidos <24h del descargue
- N viajes totales (confianza del score)
- $ promedio por zona

**Fase 1**: widget rating al cerrar viaje (inputs de los 3 actores).
**Fase 2**: rating mixto (implícito 40% + explícito 60% con decay temporal).

---

## 🧾 Módulo 6 — Facturación y cobro self-service (spec preliminar)

Decidido con Bernardo 2026-04-22. No está en el roadmap original de 5 módulos.

**Workflow 3 actores**:
```
Transportadora sube cumplido (foto + PDF)
  → Logxie verifica automático (gate: cumplidos 100%)
  → Transportadora sube factura PDF
  → Logxie valida factura vs precio adjudicado
  → Cliente Avgust ve + aprueba + paga
  → Marca pagada
```

**Cambios UI**:

| Portal | Cambios |
|---|---|
| `mi-netfleet.html` (transportadora) | Nuevo tab "💰 Facturar" con lista de viajes cerrados. Por viaje: ver cumplidos subidos + botón "Subir factura" (gate: cumplido 100%). Estado de factura: pendiente / aprobada / pagada. |
| `cliente.html` (nuevo) | Portal Avgust: ve sus viajes + cumplidos + facturas pendientes. Aprueba/paga 1-clic. Ve pagos pendientes proveedores. |
| `control.html` | Tab nuevo "🧾 Facturación" con vista global: facturas pendientes revisión, conciliaciones fallidas, alertas "factura pendiente de pago +Nd". |

**Decisiones pendientes**:
- Storage PDFs: Supabase Storage vs Google Drive (continuidad con cumplidos actuales)
- Nombre del portal cliente (¿`cliente.html`? ¿`avgust.html`?)
- Política aprobación (auto si factura = precio adjudicado, manual si delta)
- Integración con factura electrónica DIAN (Colombia) — largo plazo

**Cuándo construirlo**: cuando Módulo 1 (bidding) esté end-to-end vivo con transportadoras ofertando en Netfleet. Sin ofertas reales, facturación no tiene volumen.

---

## 🧪 Scenarios — capa de trabajo tentativa (✅ implementado 2026-04-22)

Decisión estructural motivada por descubrimiento de Bernardo: cuando armaba combinaciones tentativas, los pedidos "desaparecían" de `sin_consolidar` y no podía seguir jugando con ellos.

**Solución**: un **scenario** = propuesta tentativa de viaje que agrupa pedidos sin comprometerlos. Un pedido puede estar en N scenarios simultáneos mientras siga en `sin_consolidar`.

- Al **promover** un scenario → se crea el viaje real (vía `fn_consolidar_pedidos`), pedidos pasan a `consolidado`, otros scenarios que compartían pedidos quedan `conflictivo` para limpieza manual.
- Al **limpiar consumidos** (acción operador) → el scenario conflictivo vuelve a `borrador` con solo los pedidos libres que quedan; si no queda ninguno, pasa a `invalidado`.

**State machine scenarios**:
```
borrador ⟶ promovido (viaje X creado)
         ⟶ descartado (manual con razón)
         ⟶ conflictivo (otro scenario se llevó un pedido)
              ⟶ borrador (tras fn_scenario_limpiar_consumidos si quedan pedidos libres)
              ⟶ invalidado (si no queda ningún pedido libre)
```

**State machine pedidos** (sin cambios):
```
nuevo → sin_consolidar → consolidado → asignado → en_ruta → entregado/novedad
                      [N scenarios mientras sin_consolidar — no afectan estado]
```

Schema + functions: [db/scenarios_viaje.sql](../db/scenarios_viaje.sql). UI: sub-tab 🧪 Scenarios en [control.html](../control.html). Integración analizador: [analizador-rutas.html](../analizador-rutas.html) con selector dual Viaje/Scenario + deep-link `?scenario=<id>`.

---

## 🧭 Mapping tiles del panel → fila de journey

```
Dashboard Inicio (tab 🏠):
  📋 Revisar nuevos        🟡 → Paso 1
  📦 Listos consolidar     🟢 → Paso 2
  ⚠️ Con novedad           🔴 → Paso 6
  ✏️ Borradores viaje      🟡 → Paso 3
  🤝 Sin proveedor         🟢 → Paso 3-4
  🚛 En ruta               🟢 → Paso 5-6
  📬 Entregados pte cerrar 🟢 → Paso 6

Workspace Pedidos (tab 📥):
  Tira pistas 🟡🟢🔴       → Pasos 1, 2, 6

Workspace Viajes (tab 🚚):
  Sub-tab 🤝 Por asignar   → Pasos 3, 4
  Sub-tab 🚛 Asignados     → Pasos 5, 6
  Sub-tab 🧪 Scenarios     → Paso 2 (capa tentativa)
  Sub-tab 📚 Archivo       → Paso 6 (post-cierre)
```

---

## 📅 Changelog — reglas activadas

Formato: `YYYY-MM-DD · regla · quién · notas`

| Fecha | Evento | Notas |
|---|---|---|
| 2026-04-22 | ✅ Badge zona + sub-split por zona (regla #8) | Infra visual; no es regla autopilot pero habilita decisión manual más rápida |
| 2026-04-22 | ✅ Capa Scenarios (regla #7) | Permite exploración antes de commit. Schema + UI + analizador |
| 2026-04-22 | ✅ Analizador migrado a Supabase (regla #6) | Selector dual viaje/scenario, deep-link `?scenario=<id>` |
| — | 🔲 Regla #1 auto-swap destino↔dirección | Siguiente candidata (80 h/año) |
| — | 🔲 Regla #2 rating implícito Fase 0 | Prerequisito regla #3 |

---

## 🔗 Ver también

- [CLAUDE.md](../CLAUDE.md) — reglas, accesos, arquitectura estable
- [docs/CONTEXTO_OPERATIVO.md](CONTEXTO_OPERATIVO.md) — estado vivo del proyecto
- [docs/ARQUITECTURA.md](ARQUITECTURA.md) — profundización técnica
- [db/scenarios_viaje.sql](../db/scenarios_viaje.sql) — schema + 6 functions
- [control.html](../control.html) — panel de operación (staff)
- [analizador-rutas.html](../analizador-rutas.html) — planificador multi-parada con ETAs
