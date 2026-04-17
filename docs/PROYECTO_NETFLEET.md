# NETFLEET — Contexto del Proyecto

> Marketplace de carga B2B para Colombia — Logxie Connect S.A.S.
> Responsable: Bernardo Aristizabal · bernardoaristizabal@logxie.com · +573214401975
> Dominio: https://netfleet.app

---

## Qué es NETFLEET

Plataforma de subasta inversa de fletes terrestres en Colombia.

- **Generadores de carga** (empresas como Avgust, Fateco) publican viajes con origen, destino, peso y fecha
- **Transportadores certificados** ven los viajes y hacen ofertas — el mejor precio gana
- **Logxie** (nosotros) aprueba cuentas, modera subastas y gestiona viajes adjudicados
- +1.000 viajes completados, 7 transportadoras activas, clientes reales en operación diaria

---

## Stack Técnico

| Componente | Tecnología |
|------------|------------|
| Frontend | HTML/CSS/JS puro — sin framework ni bundler |
| Auth + DB | Supabase (PostgREST con raw fetch, JWT anon key) |
| Mapas | Leaflet 1.9.4 + CartoDB dark tiles + OSRM (rutas reales) |
| Datos viajes | Google Sheets → CSV público (n8n procesa emails → Sheet) |
| Precios | Modelo polynomial Ridge R²=0.919 (1,015 viajes reales) |
| Geocoding | Diccionario local ~200 ciudades + Google Geocoding API fallback |
| Hosting | Cloudflare Pages (auto-deploy desde GitHub push a `main`) |
| Repo | github.com/Logxie-Projects/cargachat (branch `main`) |

---

## Arquitectura de Archivos

```
index.html          → Landing del generador (hero + calculadora + mapa + viajes + subastas) ~3400 líneas
empresa.html        → Portal registro/login empresas generadoras ~815 líneas
transportador.html  → Dashboard del transportador (login + viajes + ofertas + docs) ~700 líneas
admin.html          → Panel admin Logxie (usuarios + subastas) ~770 líneas
mis-ofertas.html    → Vista de ofertas del transportador ~445 líneas
viaje.html          → Tarjeta individual de viaje (para screenshots LinkedIn) ~650 líneas
supabase.min.js     → SDK Supabase v2.39.8 local (NO cambiar versión)
_headers            → Cache-Control: no-cache para Cloudflare
```

Cada archivo HTML es self-contained (HTML + CSS + JS en un solo archivo).

---

## Flujo de Datos

```
Gmail (Avgust/Fateco envían solicitudes de transporte)
    ↓
n8n (automatización: parsea email, calcula precio con modelo Ridge, escribe en Sheet)
    ↓
Google Sheets (CSV público con viajes: origen, destino, peso, precio, fecha)
    ↓
index.html / transportador.html (cargarViajes() lee CSV y renderiza tarjetas + mapa)
    ↓
Transportador hace oferta → Supabase tabla `ofertas`
    ↓
Admin adjudica en admin.html → Logxie gestiona el viaje
```

---

## Base de Datos Supabase

**URL:** `https://pzouapqnvllaaqnmnlbs.supabase.co`

### Tabla `perfiles`
- Campos: id, email, nombre, empresa, telefono, nit
- `tipo`: 'transportador' | 'empresa'
- `estado`: 'pendiente' | 'aprobado' | 'rechazado' (NUNCA usar 'activo')
- Trigger `handle_new_user()` crea fila automáticamente al registrarse

### Tabla `ofertas`
- Campos: id, viaje_rt, usuario_id, nombre, empresa, telefono, precio_oferta, comentario
- `estado`: 'activa' | 'aceptada' | 'rechazada' | 'cancelada'
- `viaje_rt` = hash del viaje: `'v-' + Math.abs(hash).toString(36)`
- RLS activado, unique index (1 oferta activa por usuario por viaje)

**CRITICO:** Todas las queries usan raw fetch con headers `apikey` + `Authorization` (JWT anon key largo, iat:1775536019). NUNCA usar `sb_publishable_` key.

---

## Modelo de Precios

```
Para km >= 50:
  precio = 3097.69*km + 217.94*kg + 0.1215*km*kg
           - 1.0566*km² - 0.0034*kg²
           + 63186*paradas + ajusteZona - 306248
  mínimo: $950.000 COP

Para km < 50 (urbano):
  precio = max(300000, 260000 + kg*28 + 63186*(paradas-1))
```

Ajustes por zona (COP): HUB 0, ANTIOQUIA +15.7K, BOYACA +87.7K, LLANOS +159K, SANTANDERES -213K, etc.
Mismo algoritmo en frontend (estimarPrecio) y en n8n.

---

## Decisiones de Producto

1. **index.html es 100% para el generador** — la landing habla al generador de carga, no al transportador
2. **Transportador tiene su propia URL** (transportador.html) con link discreto desde el nav
3. **Hero con mini-calculadora** — sliders distancia+peso calculan precio estimado y % ahorro en tiempo real
4. **Mapa hero** — muestra viajes reales del Sheet, rota ruta+kg+precio cada 3s
5. **Viajes públicos** (pendiente implementar en transportador.html) — solo "Ofertar →" requiere login

---

## Pendientes Prioritarios

- [ ] transportador.html: viajes públicos sin login — "Ofertar →" dispara registro
- [ ] Hero badge mini-mapa: cambiar copy "transportadores pujando" por orientado al generador
- [ ] Sección viajes index.html: decidir si se quitan o reencuadran para el generador
- [ ] empresa.html: formulario publicación de carga (conectar a Supabase tabla `viajes`)
- [ ] Tabla `viajes` Supabase: migrar de Google Sheets a DB propia
- [ ] og-image.png: imagen 1200×630px para preview WhatsApp/LinkedIn

---

## Notas Técnicas Clave

- `window.open()` debe llamarse sincrónicamente en el gesture del usuario (nunca después de `await`)
- `fitBounds` siempre con `maxZoom:12` (sin esto los tiles quedan grises)
- iOS Safari: `overflow-x:hidden` en `body` rompe `position:fixed` — aplicar también a `html`
- Pins duplicados en mapa: offset de `n * 0.06°` lat para viajes del mismo origen
- Polling cada 3min busca viajes nuevos en el CSV y muestra banner si hay cambios
- Rutas reales vía OSRM (gratis, sin API key) con fallback a línea recta

---

*Última actualización: 2026-04-12*
