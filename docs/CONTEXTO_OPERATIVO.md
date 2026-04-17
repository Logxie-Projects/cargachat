# Estado actual Netfleet

> Foto del proyecto al **2026-04-17**. Este documento se actualiza conforme se avanza — leer primero para tener contexto de qué está vivo, qué falta, y dónde están los riesgos hoy.

---

## Qué está en producción hoy

### Sitio live — `netfleet.app`
- **Landing del generador** (`index.html`) con hero + mini-calculadora de precio (sliders distancia/peso) + mini-mapa con viajes reales rotando cada 3s + sección de viajes públicos + calculadora completa.
- **Portal de registro/login de empresas** (`empresa.html`) conectado a Supabase (tabla `perfiles`).
- **Dashboard del transportador** (`transportador.html`) con login, listado de viajes, flujo de ofertas, carga de documentos.
- **Panel admin Logxie** (`admin.html`) para aprobar/rechazar cuentas y gestionar subastas.
- **Mis ofertas** (`mis-ofertas.html`) con tabs activas/historial, stats, y cancelación de ofertas.
- **Check-in de ruta** (`checkderuta.html`) que envía webhook a n8n con destinatarios por viaje, persiste en localStorage.
- **Analizador de rutas** (`analizador-rutas.html`) para rutas multi-parada.

### Supabase
- **Tabla `perfiles`** con trigger `handle_new_user()` que crea fila automáticamente al registro.
- **Tabla `ofertas`** con RLS activado, unique index por `(viaje_rt, usuario_id) where estado='activa'`.
- Políticas RLS diferenciadas para SELECT / INSERT / UPDATE.

### n8n (automatización)
- Workflow procesando correos de Avgust y Fateco → parsea viajes → calcula precio con modelo Ridge v2 → escribe al Google Sheet publicado.
- Webhook de `checkderuta.html` recibiendo check-ins (workflow documentado en `n8n-checkderuta.md`).

### Datos
- **Google Sheet** publicado como CSV (gid=1690776181 desde 2026-04-16). Es la fuente de verdad de viajes hoy.
- **Modelo de precios Ridge** R²=0.919, entrenado con 1.015 viajes reales (`ViajesColombia.xlsx`, no versionado).

### Escala actual
- +1.000 viajes completados históricos.
- 7 transportadoras activas con cuenta aprobada.
- Clientes reales operando en producción todos los días.

---

## Qué está pendiente

### Producto
- [ ] **Viajes públicos en `transportador.html`** — ver viajes sin login; el modal de registro se dispara solo al hacer clic en "Ofertar →".
- [ ] **Copy del hero badge** — "TRANSPORTADORES PUJANDO" orientado al transportador, reemplazar por algo orientado al generador.
- [ ] **Decisión sobre la sección de viajes en `index.html`** — ¿se elimina del landing del generador o se reencuadra como "espacio disponible en estas rutas"?
- [ ] **Formulario de publicación de carga en `empresa.html`** — hoy el generador no puede publicar, solo registrarse. Conectar a una futura tabla `viajes` en Supabase.
- [ ] **og-image.png** (1200×630px) para preview en WhatsApp/LinkedIn.

### Ingeniería
- [ ] **Migrar fuente de viajes a Supabase** — la tabla `viajes` reemplaza al Google Sheet y elimina la dependencia del publish-to-web.
- [ ] **Cierre y adjudicación de subastas** — countdown, notificaciones al adjudicado, lock tras cierre.
- [ ] **Persistencia de check-ins en Supabase** — hoy solo viven en localStorage + webhook n8n.
- [ ] **Dashboard analytics para Logxie** — viajes por zona, ahorro promedio, tasa de adjudicación.
- [ ] **Bug 2-opt en `index.html`** (línea ~1483): fallback de `pts[j+1]` cuando j es último índice.
- [ ] **`viaje.html`** sigue usando sort por latitud en vez de nearest-neighbor/2-opt.
- [ ] **Banner de modo demo** cuando el CSV falla y se muestran los 2 viajes hardcoded (hoy no hay aviso visible).
- [ ] **Rangos históricos del estimador** son estáticos — actualizar periódicamente con datos nuevos.

### Operación
- [ ] **Plan de contingencia si el Publish-to-Web del Sheet se rompe** — hoy hay fallback a 2 viajes hardcoded pero sin alerta. Documentar runbook.
- [ ] **Precios de viajes viejos del Sheet** calculados con n8n v1 (fórmula lineal antigua). Solo los nuevos usan Ridge v2.

---

## Próximos pasos inmediatos

1. **Base limpia del repo** ← esta tarea (organización de archivos + docs estructurados).
2. **Definir decisión sobre la sección de viajes en `index.html`** — bloquea el copy del hero y decisiones de layout.
3. **Implementar viajes públicos en `transportador.html`** — desbloquea conversión de transportadores.
4. **Diseñar esquema de la tabla `viajes`** en Supabase — base para ingesta multicliente y para independizarse del Sheet.
5. **Agregar countdown y notificación de adjudicación** a la subasta — cierra el loop del core del producto.

---

## Notas operativas

### Sensibilidades
- **Google Sheet publish-to-web**: la pestaña publicada hoy es `gid=1690776181`. Si se detiene o se cambia, `netfleet.app` cae a modo demo con 2 viajes hardcoded. Ver `CLAUDE.md` → sección *Publish-to-Web del Google Sheet* para el runbook completo.
- **Supabase anon key**: usar el JWT largo (iat:1775536019). **NUNCA** el `sb_publishable_`. Todas las queries PostgREST son raw fetch con headers explícitos.
- **`estado: 'aprobado'`** (no `'activo'`) en la tabla `perfiles`. Todo el frontend depende de este string exacto.

### Deploy
- Push a `main` → Cloudflare Pages auto-deploy en ~1-2 minutos.
- No hay staging. Probar local antes de pushear.
- `_headers` fuerza `Cache-Control: no-cache` para que el HTML nuevo llegue al usuario de inmediato.

### Contacto responsable
- **Bernardo Aristizabal** — bernardoaristizabal@logxie.com — +573214401975
- Empresa: **Logxie Connect S.A.S.**

### Enlaces clave
- Producción: https://netfleet.app
- Repo: https://github.com/Logxie-Projects/cargachat (branch `main`)
- Supabase: https://pzouapqnvllaaqnmnlbs.supabase.co
- Admin panel: https://netfleet.app/admin.html

---

*Última actualización: 2026-04-17*
