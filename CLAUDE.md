# NETFLEET — Guía para Claude Code

> Marketplace de carga B2B para Colombia — Logxie Connect S.A.S.
> Responsable: Bernardo Aristizabal · bernardoaristizabal@logxie.com · +573214401975

---

## Contexto del Proyecto

Plataforma de subasta inversa de fletes:
- **Generadores de carga** (empresas como Avgust, Fateco) publican viajes
- **Transportadores certificados** hacen ofertas — el mejor precio gana
- **Logxie** aprueba cuentas, gestiona viajes adjudicados
- +1.000 viajes completados, 7 transportadoras activas, clientes reales en operación diaria

---

## Rutas y Accesos

| Recurso | Valor |
|---------|-------|
| Carpeta local | `D:\Proyecto Avgust\Netlify v3\` |
| GitHub repo | `https://github.com/Logxie-Projects/cargachat` (branch `main`) |
| Sitio en vivo | `https://netfleet.app` |
| Cloudflare Pages | `cargachat.pages.dev` (auto-deploy al hacer push a `main`) |
| Supabase URL | `https://pzouapqnvllaaqnmnlbs.supabase.co` |
| Admin panel | `https://netfleet.app/admin.html` |
| Admin email | `bernardoaristizabal@logxie.com` |
| Admin WA | `+573214401975` |

**Deploy:** `git add archivo.html && git commit -m "descripción" && git push origin main`
Cloudflare despliega automáticamente en ~1-2 minutos.

---

## Archivos Principales

```
index.html          → Landing del generador (TODO en un archivo: HTML+CSS+JS)
empresa.html        → Portal de registro/login para empresas generadoras
transportador.html  → Dashboard del transportador (login + viajes + ofertas + docs)
admin.html          → Panel admin Logxie (usuarios + subastas)
mis-ofertas.html    → Vista de ofertas del transportador
supabase.min.js     → SDK Supabase v2.39.8 local (NO cambiar versión)
_headers            → Cache-Control: no-cache para Cloudflare
```

---

## Stack Técnico

- **Frontend:** HTML/CSS/JS puro — sin framework
- **Mapas:** Leaflet.js v1.9.4 + CartoDB dark tiles
- **Auth & DB:** Supabase (raw fetch, NO usar el cliente sb para PostgREST)
- **Datos de viajes:** Google Sheets → CSV público → `CSV_URL` en index.html
- **Geocoding:** Diccionario local `CIUDADES` (~200 ciudades) + Google Geocoding API fallback
- **Precios:** Modelo polynomial Ridge R²=0.919 entrenado con 1.015 viajes reales

**CRÍTICO — Supabase:** Usar siempre el JWT anon key largo (iat:1775536019). NUNCA el `sb_publishable_` key. Todas las queries PostgREST usan raw fetch con headers explícitos `apikey` + `Authorization`.

---

## Decisiones Estratégicas Tomadas

### index.html — Landing 100% para el Generador
La bifurcación "¿Empresa o Transportador?" fue eliminada. La landing habla exclusivamente al generador. El transportador tiene su propia URL (`transportador.html`). El nav tiene un link discreto "¿Eres transportador?" para quienes llegan por error.

### Hero con Mini-Calculadora
El hero tiene dos sliders (distancia + peso) que calculan en tiempo real el precio estimado y el % de ahorro vs mercado. La calculadora usa `estimarPrecio()` + `ccRango()` definidas en el bloque de la calculadora completa. La función del hero se llama `hcCalc()`.

### Mapa Hero (mini-mapa)
- Lee viajes reales del Google Sheet via `_heroDrawFn(viajesData)` llamada desde `cargarViajes()` al finalizar
- Usa `getCoordenadas()` + `geocodeCiudad()` (mismo sistema que el mapa principal)
- Rota ruta + kg disponibles + precio real cada 3s
- El badge actual dice "TRANSPORTADORES PUJANDO" — pendiente revisar copy para generador

### Sección de Viajes en index.html
Pendiente de decisión: ¿se eliminan las tarjetas de viaje del landing del generador o se reencuadran como "espacio disponible en estas rutas"? El argumento para dejarlas: si la ruta del generador aparece, le llama la atención. El argumento para quitarlas: confunden al generador (¿son precios que le cobrarán?).

### transportador.html — Ver antes de registrarse
Decisión pendiente de implementar: los viajes deben ser públicos (sin login). Solo al hacer clic en "Ofertar →" se dispara el modal de registro/login. Esto aumenta la conversión del transportador.

---

## Flujo de Datos

```
Gmail (Avgust/Fateco) → n8n → Google Sheets (CSV público)
                                      ↓
                            index.html cargarViajes()
                                      ↓
                     Transportador hace oferta → Supabase tabla `ofertas`
                                      ↓
                     Admin adjudica en admin.html
                                      ↓
                             Logxie gestiona el viaje
```

---

## Base de Datos Supabase

### Tabla `perfiles`
```
id, email, nombre, empresa, telefono, nit
tipo: 'transportador' | 'empresa'
estado: 'pendiente' | 'aprobado' | 'rechazado'
```
**Trigger:** `handle_new_user()` crea la fila automáticamente al registrarse.
**IMPORTANTE:** el código chequea `estado === 'aprobado'` en todo el frontend. NO usar `'activo'`.

### Tabla `ofertas`
```
id, viaje_rt (hash del viaje), usuario_id, nombre, empresa, telefono
precio_oferta, comentario
estado: 'activa' | 'aceptada' | 'rechazada' | 'cancelada'
```
`viaje_rt` = hash generado así: `'v-' + Math.abs(hash).toString(36)` — mismo algoritmo en frontend y admin.

---

## Algoritmo de Precio

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
Mismo algoritmo en n8n (nodo JS). Zonas: ANTIOQUIA +15.7K, BOYACA +87.7K, LLANOS +159K, SANTANDERES -213K, etc.

---

## Pendientes Prioritarios

- [ ] **transportador.html:** viajes públicos sin login — "Ofertar →" dispara registro
- [ ] **Hero badge mini-mapa:** cambiar "transportadores pujando" por copy orientado al generador
- [ ] **Sección viajes index.html:** decidir si se quitan o se reencuadran
- [ ] **empresa.html:** formulario de publicación de carga (conectar a Supabase tabla `viajes`)
- [ ] **Tabla `viajes` Supabase:** migrar de Google Sheets a DB propia
- [ ] **og-image.png:** imagen 1200×630px para preview WhatsApp/LinkedIn

---

## Notas Técnicas Importantes

- `window.open()` debe llamarse sincrónicamente en el gesture del usuario — nunca después de `await`
- `fitBounds` siempre con `maxZoom:12` — sin esto los tiles Leaflet quedan grises
- iOS Safari: `overflow-x:hidden` en `body` rompe `position:fixed` — aplicarlo también al elemento `html`
- FAB flotante: `right:6px` por defecto, `right:24px` en `@media(min-width:769px)`
- Pins duplicados en el mapa: offset de `n * 0.06°` lat para viajes del mismo origen
- `tipo_mercancia`: `(v.tipo_mercancia || '').trim() || 'General'`
