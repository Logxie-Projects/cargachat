# Contexto de sesión — NETFLEET
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
