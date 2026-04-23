/* ================================================================
 * netfleet-core.js — módulo compartido de geocoding
 *
 * Fuente única del diccionario CIUDADES + helpers de búsqueda (getCoordenadas,
 * normalizarNombre, variantes, extraerCiudad, geocodeCiudad).
 *
 * Se carga con `<script src="netfleet-core.js"></script>` ANTES del inline
 * script de la página. Las 5 páginas que antes tenían su propia copia
 * (index, transportador, analizador-rutas, viaje, mi-netfleet) ya no
 * declaran CIUDADES local y heredan este global.
 *
 * Cualquier cambio al catálogo de ciudades se hace acá, único lugar.
 * ================================================================ */

/* -----------------------------------------------------------
 * CIUDADES — coordenadas [lat, lng] por ciudad canónica
 * ----------------------------------------------------------- */
const CIUDADES = {
  // ── Bodegas principales Logxie / Avgust ──
  'funza':   [4.7132, -74.1966],
  'yumbo':   [3.5928, -76.4944],
  'espinal': [4.1544, -74.8864],

  // ── Ciudades principales ──
  'bogota':        [4.7110, -74.0721],
  'bogotá':        [4.7110, -74.0721],
  'cali':          [3.4516, -76.5319],
  'medellin':      [6.2442, -75.5812],
  'medellín':      [6.2442, -75.5812],
  'barranquilla':  [10.9685, -74.7813],
  'cartagena':     [10.3910, -75.4794],
  'cucuta':        [7.8939, -72.5078],
  'cúcuta':        [7.8939, -72.5078],
  'bucaramanga':   [7.1253, -73.1198],
  'santa marta':   [11.2408, -74.2110],
  'monteria':      [8.7575, -75.8906],
  'montería':      [8.7575, -75.8906],
  'valledupar':    [10.4631, -73.2532],
  'riohacha':      [11.5444, -72.9072],
  'sincelejo':     [9.3047, -75.3978],
  'neiva':         [2.9273, -75.2820],
  'ibague':        [4.4389, -75.2322],
  'ibagué':        [4.4389, -75.2322],
  'villavicencio': [4.1420, -73.6266],
  'aguachica':     [8.3081, -73.6189],

  // ── Eje Cafetero ──
  'manizales':          [5.0703, -75.5138],
  'pereira':            [4.8087, -75.6906],
  'armenia':            [4.5339, -75.6811],
  'cartago':            [4.7454, -75.9120],
  'la virginia':        [4.9000, -75.8833],
  'dosquebradas':       [4.8378, -75.6742],
  'santa rosa de cabal':[4.8680, -75.6256],
  'santa rosa':         [4.8680, -75.6256],
  'chinchina':          [4.9815, -75.6091],
  'chinchiná':          [4.9815, -75.6091],
  'calarca':            [4.5225, -75.6437],
  'calarcá':            [4.5225, -75.6437],
  'montenegro':         [4.5662, -75.7497],
  'quimbaya':           [4.6227, -75.7636],
  'belalcazar':         [4.9936, -75.8131],
  'belalcázar':         [4.9936, -75.8131],

  // ── Boyacá (zona frecuente de Avgust) ──
  'tunja':              [5.5353, -73.3678],
  'duitama':            [5.8281, -73.0297],
  'sogamoso':           [5.7150, -72.9267],
  'paipa':              [5.7833, -73.1167],
  'ramiriqui':          [5.4000, -73.3333],
  'ramiriquí':          [5.4000, -73.3333],
  'chiquinquira':       [5.6167, -73.8167],
  'chiquinquirá':       [5.6167, -73.8167],
  'buenavista':         [5.7167, -73.9667],
  'ventaquemada':       [5.3681, -73.5194],
  'sachica':            [5.6667, -73.6833],
  'jenesano':           [5.3850, -73.3694],
  'jenessano':          [5.3833, -73.4167],
  'jenesano de boyaca': [5.3833, -73.4167],
  'jenesano boyaca':    [5.3833, -73.4167],
  'tuta':               [5.6667, -73.2000],
  'toca':               [5.5667, -73.1667],
  'tibana':             [5.3167, -73.3833],
  'tibaná':             [5.3167, -73.3833],
  'arcabuco':           [5.7667, -73.4333],
  'macheta':            [5.0850, -73.6103],
  'machetá':            [5.0850, -73.6103],
  'umbita':             [5.3000, -73.5167],
  'aquitania':          [5.5167, -72.8833],
  'saboya':             [5.6975, -73.7633],
  'saboyá':             [5.6975, -73.7633],
  'samaca':             [5.4925, -73.4856],
  'samacá':             [5.4925, -73.4856],
  'sutamarchan':        [5.6333, -73.7833],
  'miraflores':         [5.1981, -73.1456],
  'soraca':             [5.5069, -73.3342],
  'soracá':             [5.5069, -73.3342],
  'garagoa':            [5.0833, -73.3500],
  'moniquira':          [5.8775, -73.5728],
  'moniquirá':          [5.8775, -73.5728],
  'puerto boyaca':      [5.9753, -74.5875],
  'puerto boyacá':      [5.9753, -74.5875],
  'tenza':              [5.0792, -73.4244],
  'guateque':           [5.0025, -73.4711],
  'santa rosa de viterbo':[5.8742, -72.9814],
  'otanche':            [5.6556, -74.1833],
  'tibasosa':           [5.7447, -72.9983],
  'nobsa':              [5.7689, -72.9397],
  'ciénega':            [5.4111, -73.2889],
  'cienega':            [5.4111, -73.2889],

  // ── Cundinamarca ──
  'siberia':      [4.8856, -74.1483],
  'cabrera':      [3.9847, -74.4856],
  'fusagasuga':   [4.3367, -74.3644],
  'fusagasugá':   [4.3367, -74.3644],
  'silvania':     [4.4000, -74.4833],
  'sibate':       [4.4878, -74.2597],
  'sibaté':       [4.4878, -74.2597],
  'san bernardo': [4.1833, -74.4333],
  'usme':         [4.4367, -74.1322],
  'subachoque':   [4.9167, -74.2667],
  'fomeque':      [4.4833, -73.9000],
  'fómeque':      [4.4833, -73.9000],
  'ortigal':      [3.2798, -76.3449],
  'tenjo':        [4.8714, -74.1436],
  'zipaquira':    [5.0228, -74.0061],
  'zipaquirá':    [5.0228, -74.0061],
  'facatativa':   [4.8142, -74.3597],
  'facatativá':   [4.8142, -74.3597],
  'mosquera':     [4.7066, -74.2303],
  'madrid':       [4.7339, -74.2644],
  'soacha':       [4.5797, -74.2167],
  'chia':         [4.8614, -73.9314],
  'chía':         [4.8614, -73.9314],
  'cajica':       [4.9186, -74.0028],
  'cajicá':       [4.9186, -74.0028],
  'tocancipa':    [4.9678, -73.9139],
  'tocancipá':    [4.9678, -73.9139],
  'gachancipa':   [4.9969, -73.8717],
  // Municipios rurales Cundinamarca (añadidos 2026-04-22 para scenarios rurales)
  'choconta':     [5.1436, -73.6853],
  'chocontá':     [5.1436, -73.6853],
  'villapinzon':  [5.2167, -73.5833],
  'villapinzón':  [5.2167, -73.5833],
  'cogua':        [5.0611, -73.9794],
  'sasaima':      [4.9667, -74.4333],
  'susa':         [5.4500, -73.8167],
  'nocaima':      [5.0667, -74.3833],
  'quipile':      [4.7458, -74.5311],
  'cachipay':     [4.7333, -74.4333],
  'la mesa':      [4.6333, -74.4667],
  'sopo':         [4.9137, -73.9411],
  'sopó':         [4.9137, -73.9411],
  'guasca':       [4.8683, -73.8767],
  'ubate':        [5.3150, -73.8169],
  'ubaté':        [5.3150, -73.8169],
  'simijaca':     [5.5022, -73.8508],
  'guatavita':    [4.9358, -73.8319],
  'junin':        [4.7889, -73.6667],
  'junín':        [4.7889, -73.6667],
  'tausa':        [5.1972, -73.8903],
  'pacho':        [5.1333, -74.1667],
  'caqueza':      [4.4053, -73.9406],
  'cáqueza':      [4.4053, -73.9406],
  'une':          [4.4028, -73.9922],
  'choachi':      [4.5289, -73.9228],
  'choachí':      [4.5289, -73.9228],
  'ubaque':       [4.4833, -73.9333],
  'fosca':        [4.3411, -73.9403],
  'nemocon':      [5.0711, -73.8778],
  'nemocón':      [5.0711, -73.8778],
  'lenguazaque':  [5.3072, -73.7114],

  // ── Santander / Norte de Santander ──
  'barrancabermeja': [7.0653, -73.8546],
  'giron':           [7.0725, -73.1686],
  'girón':           [7.0725, -73.1686],
  'floridablanca':   [7.0639, -73.0880],
  'piedecuesta':     [6.9868, -73.0522],
  'lebrija':         [7.1167, -73.2167],
  'san gil':         [6.5567, -73.1356],
  'socorro':         [6.5133, -73.2642],
  'velez':           [6.0125, -73.6778],
  'vélez':           [6.0125, -73.6778],
  'barbosa':         [5.9364, -73.6189],

  // ── Llanos Orientales ──
  'yopal':           [5.3378, -72.3952],
  'arauca':          [7.0897, -70.7617],
  'acacias':         [3.9894, -73.7597],
  'granada':         [3.5461, -73.7229],
  'aguazul':         [5.1739, -72.5506],
  'puerto lopez':    [4.0847, -72.9583],
  'restrepo':        [4.2572, -73.5703],
  'cumaral':         [4.2708, -73.4864],

  // ── Sur (Cauca, Nariño, Putumayo) ──
  'pasto':           [1.2136, -77.2811],
  'popayan':         [2.4448, -76.6147],
  'popayán':         [2.4448, -76.6147],
  'mocoa':           [1.1520, -76.6481],
  'florencia':       [1.6144, -75.6062],
  'el tigre':        [0.3500, -75.1833],
  'puerto asis':     [0.5000, -76.5000],
  'puerto asís':     [0.5000, -76.5000],
  'orito':           [0.6667, -76.8667],
  'la hormiga':      [0.0833, -76.9000],
  'sibundoy':        [1.2000, -76.9167],
  'villagarzon':     [1.0333, -76.6167],
  'villagarzón':     [1.0333, -76.6167],

  // ── Valle del Cauca ──
  'palmira':         [3.5394, -76.3036],
  'buga':            [3.9006, -76.3032],
  'tulua':           [4.0847, -76.1992],
  'tuluá':           [4.0847, -76.1992],
  'buenaventura':    [3.8824, -77.0193],
  'girardot':        [4.3022, -74.8020],

  // ── Antioquia ──
  'rionegro':        [6.1553, -75.3742],

  // ── Capitales departamentales adicionales ──
  'leticia':         [-4.2153, -69.9401],
  'mitu':            [1.2531, -70.2333],
  'puerto inirida':  [3.8653, -67.9239],
  'san jose del guaviare': [2.5694, -72.6416],
  'quibdo':          [5.6919, -76.6583],
  'quibdó':          [5.6919, -76.6583],
  'puerto carreno':  [6.1893, -67.4841],
};

/* -----------------------------------------------------------
 * Cache y config geocoding
 * ----------------------------------------------------------- */
const geocodeCache = {};
const GMAPS_KEY = 'AIzaSyBSDer_Cdp3pNhZrebp6h5OWDfHQkWJifo';

/* -----------------------------------------------------------
 * Helpers de normalización y búsqueda
 * ----------------------------------------------------------- */

function normalizarNombre(str) {
  return (str || '').toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[.\-_()]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

// Genera variantes del nombre para buscar en el diccionario:
//   "Jenesano de Boyacá"  → ["jenesano de boyaca", "jenesano", "de boyaca"]
//   "San Gil (Santander)" → ["san gil santander", "san gil", "santander"]
function variantes(nombre) {
  const base = normalizarNombre(nombre);
  if (!base) return [];
  const partes = base.split(' ');
  const vs = [base];
  const stopwords = ['de', 'del', 'la', 'el', 'los', 'las', 'y'];
  for (let i = 1; i < partes.length; i++) {
    if (stopwords.includes(partes[i - 1]) || stopwords.includes(partes[i])) {
      vs.push(partes.slice(0, i).join(' '));
      vs.push(partes.slice(i + 1).join(' '));
    }
  }
  if (partes[0] && partes[0].length > 4) vs.push(partes[0]);
  return [...new Set(vs.filter(Boolean))];
}

// Busca coordenadas en el diccionario local.
// Pass 1: exact match. Pass 2: substring solo para candidatos ≥5 chars
// (evita que "santa" matchee "santa marta").
function getCoordenadas(ciudad) {
  if (!ciudad) return null;
  const cands = variantes(ciudad);
  for (const c of cands) {
    for (const [nombre, coords] of Object.entries(CIUDADES)) {
      if (normalizarNombre(nombre) === c) return coords;
    }
  }
  for (const c of cands) {
    if (c.length < 5) continue;
    for (const [nombre, coords] of Object.entries(CIUDADES)) {
      const n = normalizarNombre(nombre);
      if (n.includes(c) || c.includes(n)) return coords;
    }
  }
  return null;
}

// Google Geocoding API fallback con timeout de 6s.
async function geocodeCiudad(ciudad) {
  if (!ciudad) return null;
  const key = ciudad.toLowerCase().trim();
  if (geocodeCache[key]) return geocodeCache[key];
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    const r = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(ciudad + ', Colombia')}&key=${GMAPS_KEY}`,
      { signal: ctrl.signal }
    );
    clearTimeout(t);
    const d = await r.json();
    if (d.results && d.results.length > 0) {
      const l = d.results[0].geometry.location;
      const c = [l.lat, l.lng];
      geocodeCache[key] = c;
      return c;
    }
  } catch (e) {
    console.warn('[geocode] timeout/error para', ciudad, e.message);
  }
  return null;
}

// Atajo: local primero, API fallback.
async function getCoords(ciudad) {
  return getCoordenadas(ciudad) || await geocodeCiudad(ciudad);
}

// Wrapper con nombre: devuelve {lat, lng, name} o null.
function geo(name) {
  const c = getCoordenadas(name);
  return c ? { lat: c[0], lng: c[1], name: (name || '').trim() } : null;
}

// Extrae la ciudad real desde un destino verbose tipo "CENTRO OCOBOS ESPINAL"
// o "PPAL 3PL SAN DIEGO FUNZA" buscando dentro de los tokens cuál matchea una
// ciudad conocida. Fallback: el texto original (dejá que Google intente).
function extraerCiudad(destino) {
  if (!destino) return '';
  if (getCoordenadas(destino)) return destino;
  const tokens = destino.split(/[\s,;\/()\-]+/).filter(t => t && t.length >= 3);
  for (let i = 0; i < tokens.length - 1; i++) {
    const par = tokens[i] + ' ' + tokens[i + 1];
    if (getCoordenadas(par)) return par;
  }
  for (let i = tokens.length - 1; i >= 0; i--) {
    if (getCoordenadas(tokens[i])) return tokens[i];
  }
  return destino;
}

/* -----------------------------------------------------------
 * CORREDORES — mapeo ciudad canónica (lowercase) → corredor logístico.
 * Un "corredor" es una agrupación de ciudades que naturalmente viajan
 * juntas en una ruta consolidada. Usado por "Agrupar por LogxIA" para
 * transcender las zonas administrativas (que dependen del cliente y
 * no siempre reflejan la lógica de ruteo real).
 *
 * Ejemplo clave: Villapinzón (Cundinamarca) está en el mismo corredor
 * que Tunja (Boyacá) porque la ruta Funza→Tunja pasa por Villapinzón.
 * Las zonas dicen distinto, la ruta real dice igual.
 *
 * Validado con histórico de 1.297 viajes (pares frecuentes como
 * Armenia-Chinchiná 43x, Tunja-Villapinzón 18x, Pasto-Popayán 29x).
 * ----------------------------------------------------------- */
const CORREDORES = {
  // ── VALLE (origen+destino intra-Valle) ──
  'yumbo':'VALLE', 'cali':'VALLE', 'palmira':'VALLE', 'buga':'VALLE',
  'tulua':'VALLE', 'tuluá':'VALLE', 'ginebra':'VALLE', 'girardot':'VALLE',
  'buenaventura':'VALLE',

  // ── EJE CAFETERO ──
  'manizales':'EJE CAFETERO', 'pereira':'EJE CAFETERO',
  'armenia':'EJE CAFETERO', 'cartago':'EJE CAFETERO',
  'la virginia':'EJE CAFETERO', 'dosquebradas':'EJE CAFETERO',
  'santa rosa de cabal':'EJE CAFETERO', 'santa rosa':'EJE CAFETERO',
  'chinchina':'EJE CAFETERO', 'chinchiná':'EJE CAFETERO',
  'calarca':'EJE CAFETERO', 'calarcá':'EJE CAFETERO',
  'montenegro':'EJE CAFETERO', 'quimbaya':'EJE CAFETERO',
  'belalcazar':'EJE CAFETERO', 'belalcázar':'EJE CAFETERO',
  'la union':'EJE CAFETERO',  // La Unión-Valle (histórico aparece 15x con Armenia)

  // ── BOYACÁ-CUNDINAMARCA (mega-corredor centro-oriente) ──
  // Funza es hub, pero como destino cae acá. La ruta Funza→Tunja pasa
  // por Villapinzón, Chocontá (Cund) → Ventaquemada, Tuta (Boy).
  'funza':'BOYACA-CUNDINAMARCA',
  'bogota':'BOYACA-CUNDINAMARCA', 'bogotá':'BOYACA-CUNDINAMARCA',
  'soacha':'BOYACA-CUNDINAMARCA', 'chia':'BOYACA-CUNDINAMARCA', 'chía':'BOYACA-CUNDINAMARCA',
  'cajica':'BOYACA-CUNDINAMARCA', 'cajicá':'BOYACA-CUNDINAMARCA',
  'tocancipa':'BOYACA-CUNDINAMARCA', 'tocancipá':'BOYACA-CUNDINAMARCA',
  'mosquera':'BOYACA-CUNDINAMARCA', 'madrid':'BOYACA-CUNDINAMARCA',
  'fusagasuga':'BOYACA-CUNDINAMARCA', 'fusagasugá':'BOYACA-CUNDINAMARCA',
  'sibate':'BOYACA-CUNDINAMARCA', 'sibaté':'BOYACA-CUNDINAMARCA',
  'silvania':'BOYACA-CUNDINAMARCA', 'san bernardo':'BOYACA-CUNDINAMARCA',
  'subachoque':'BOYACA-CUNDINAMARCA', 'tenjo':'BOYACA-CUNDINAMARCA',
  'zipaquira':'BOYACA-CUNDINAMARCA', 'zipaquirá':'BOYACA-CUNDINAMARCA',
  'facatativa':'BOYACA-CUNDINAMARCA', 'facatativá':'BOYACA-CUNDINAMARCA',
  'siberia':'BOYACA-CUNDINAMARCA', 'gachancipa':'BOYACA-CUNDINAMARCA',
  'choconta':'BOYACA-CUNDINAMARCA', 'chocontá':'BOYACA-CUNDINAMARCA',
  'villapinzon':'BOYACA-CUNDINAMARCA', 'villapinzón':'BOYACA-CUNDINAMARCA',
  'cogua':'BOYACA-CUNDINAMARCA', 'susa':'BOYACA-CUNDINAMARCA',
  'sopo':'BOYACA-CUNDINAMARCA', 'sopó':'BOYACA-CUNDINAMARCA',
  'guasca':'BOYACA-CUNDINAMARCA', 'ubate':'BOYACA-CUNDINAMARCA', 'ubaté':'BOYACA-CUNDINAMARCA',
  'simijaca':'BOYACA-CUNDINAMARCA', 'guatavita':'BOYACA-CUNDINAMARCA',
  'tausa':'BOYACA-CUNDINAMARCA', 'pacho':'BOYACA-CUNDINAMARCA',
  'nemocon':'BOYACA-CUNDINAMARCA', 'nemocón':'BOYACA-CUNDINAMARCA',
  'lenguazaque':'BOYACA-CUNDINAMARCA', 'cabrera':'BOYACA-CUNDINAMARCA',
  'la mesa':'BOYACA-CUNDINAMARCA', 'cachipay':'BOYACA-CUNDINAMARCA',
  'sasaima':'BOYACA-CUNDINAMARCA', 'nocaima':'BOYACA-CUNDINAMARCA',
  'quipile':'BOYACA-CUNDINAMARCA', 'junin':'BOYACA-CUNDINAMARCA', 'junín':'BOYACA-CUNDINAMARCA',
  'usme':'BOYACA-CUNDINAMARCA', 'fomeque':'BOYACA-CUNDINAMARCA', 'fómeque':'BOYACA-CUNDINAMARCA',
  'caqueza':'BOYACA-CUNDINAMARCA', 'cáqueza':'BOYACA-CUNDINAMARCA',
  'une':'BOYACA-CUNDINAMARCA', 'choachi':'BOYACA-CUNDINAMARCA', 'choachí':'BOYACA-CUNDINAMARCA',
  'ubaque':'BOYACA-CUNDINAMARCA', 'fosca':'BOYACA-CUNDINAMARCA',
  'ortigal':'BOYACA-CUNDINAMARCA',
  // Boyacá
  'tunja':'BOYACA-CUNDINAMARCA', 'duitama':'BOYACA-CUNDINAMARCA',
  'sogamoso':'BOYACA-CUNDINAMARCA', 'paipa':'BOYACA-CUNDINAMARCA',
  'ramiriqui':'BOYACA-CUNDINAMARCA', 'ramiriquí':'BOYACA-CUNDINAMARCA',
  'chiquinquira':'BOYACA-CUNDINAMARCA', 'chiquinquirá':'BOYACA-CUNDINAMARCA',
  'buenavista':'BOYACA-CUNDINAMARCA', 'ventaquemada':'BOYACA-CUNDINAMARCA',
  'sachica':'BOYACA-CUNDINAMARCA', 'jenesano':'BOYACA-CUNDINAMARCA',
  'jenessano':'BOYACA-CUNDINAMARCA', 'jenesano de boyaca':'BOYACA-CUNDINAMARCA',
  'jenesano boyaca':'BOYACA-CUNDINAMARCA',
  'tuta':'BOYACA-CUNDINAMARCA', 'toca':'BOYACA-CUNDINAMARCA',
  'tibana':'BOYACA-CUNDINAMARCA', 'tibaná':'BOYACA-CUNDINAMARCA',
  'arcabuco':'BOYACA-CUNDINAMARCA', 'macheta':'BOYACA-CUNDINAMARCA', 'machetá':'BOYACA-CUNDINAMARCA',
  'umbita':'BOYACA-CUNDINAMARCA', 'aquitania':'BOYACA-CUNDINAMARCA',
  'saboya':'BOYACA-CUNDINAMARCA', 'saboyá':'BOYACA-CUNDINAMARCA',
  'samaca':'BOYACA-CUNDINAMARCA', 'samacá':'BOYACA-CUNDINAMARCA',
  'sutamarchan':'BOYACA-CUNDINAMARCA', 'miraflores':'BOYACA-CUNDINAMARCA',
  'soraca':'BOYACA-CUNDINAMARCA', 'soracá':'BOYACA-CUNDINAMARCA',
  'garagoa':'BOYACA-CUNDINAMARCA', 'moniquira':'BOYACA-CUNDINAMARCA', 'moniquirá':'BOYACA-CUNDINAMARCA',
  'puerto boyaca':'BOYACA-CUNDINAMARCA', 'puerto boyacá':'BOYACA-CUNDINAMARCA',
  'tenza':'BOYACA-CUNDINAMARCA', 'guateque':'BOYACA-CUNDINAMARCA',
  'santa rosa de viterbo':'BOYACA-CUNDINAMARCA', 'otanche':'BOYACA-CUNDINAMARCA',
  'tibasosa':'BOYACA-CUNDINAMARCA', 'nobsa':'BOYACA-CUNDINAMARCA',
  'cienega':'BOYACA-CUNDINAMARCA', 'ciénega':'BOYACA-CUNDINAMARCA',

  // ── HUILA-TOLIMA (central, parada entre Bogotá y sur) ──
  'ibague':'HUILA-TOLIMA', 'ibagué':'HUILA-TOLIMA',
  'espinal':'HUILA-TOLIMA', 'neiva':'HUILA-TOLIMA',

  // ── SANTANDERES ──
  'bucaramanga':'SANTANDERES', 'cucuta':'SANTANDERES', 'cúcuta':'SANTANDERES',
  'barrancabermeja':'SANTANDERES', 'giron':'SANTANDERES', 'girón':'SANTANDERES',
  'floridablanca':'SANTANDERES', 'piedecuesta':'SANTANDERES',
  'lebrija':'SANTANDERES', 'san gil':'SANTANDERES', 'socorro':'SANTANDERES',
  'velez':'SANTANDERES', 'vélez':'SANTANDERES', 'barbosa':'SANTANDERES',
  'aguachica':'SANTANDERES',

  // ── LLANOS ──
  'villavicencio':'LLANOS', 'yopal':'LLANOS', 'arauca':'LLANOS',
  'acacias':'LLANOS', 'granada':'LLANOS', 'aguazul':'LLANOS',
  'puerto lopez':'LLANOS', 'restrepo':'LLANOS', 'cumaral':'LLANOS',

  // ── SUR (Cauca, Nariño, Putumayo) ──
  'pasto':'SUR', 'popayan':'SUR', 'popayán':'SUR',
  'mocoa':'SUR', 'florencia':'SUR', 'el tigre':'SUR',
  'puerto asis':'SUR', 'puerto asís':'SUR', 'orito':'SUR',
  'la hormiga':'SUR', 'sibundoy':'SUR',
  'villagarzon':'SUR', 'villagarzón':'SUR',

  // ── COSTA NORTE ──
  'barranquilla':'COSTA', 'cartagena':'COSTA', 'santa marta':'COSTA',
  'monteria':'COSTA', 'montería':'COSTA', 'valledupar':'COSTA',
  'riohacha':'COSTA', 'sincelejo':'COSTA',

  // ── ANTIOQUIA ──
  'medellin':'ANTIOQUIA', 'medellín':'ANTIOQUIA', 'rionegro':'ANTIOQUIA',

  // ── REMOTOS / AMAZONÍA ──
  'leticia':'REMOTO', 'mitu':'REMOTO', 'puerto inirida':'REMOTO',
  'san jose del guaviare':'REMOTO', 'quibdo':'REMOTO', 'quibdó':'REMOTO',
  'puerto carreno':'REMOTO',
};

/* -----------------------------------------------------------
 * Ridge pricing — MISMA fórmula que transportador.html/index.html
 * (función PROTEGIDA per CLAUDE.md — NO modificar sin instrucción).
 * Portada acá para que LogxIA pueda estimar flete a nivel de grupo
 * de pedidos sin-consolidar y calcular $/kg, $/km, %flete/valor.
 *
 * R²=0.919 entrenada con 1.015 viajes reales.
 * ----------------------------------------------------------- */
const CC_ZONA_AJUSTE = {
  'HUB':0, 'ANTIOQUIA':15759, 'BOYACA':87756, 'CENTRO':22045,
  'CUNDINAMARCA':65602, 'EJE CAFETERO':-18794, 'LLANOS':159210,
  'NORTE':79189, 'OCCIDENTE':10720, 'ORIENTE':-176447,
  'SANTANDERES':-213483, 'SUR':79189, 'TOLHUIL':-18146, 'VALLE':34226
};

// Mapeo corredor logístico (LogxIA) → zona-ajuste (Ridge).
// Los corredores son conceptuales, el ajuste Ridge está en otra taxonomía.
const CORREDOR_A_AJUSTE = {
  'VALLE':              'VALLE',
  'EJE CAFETERO':       'EJE CAFETERO',
  'BOYACA-CUNDINAMARCA':'BOYACA',     // usar el más caro (Boyacá rural domina el viaje)
  'HUILA-TOLIMA':       'TOLHUIL',
  'SANTANDERES':        'SANTANDERES',
  'LLANOS':             'LLANOS',
  'SUR':                'SUR',
  'COSTA':              'NORTE',
  'ANTIOQUIA':          'ANTIOQUIA',
  'REMOTO':             'HUB'        // sin ajuste — no hay data
};

// Fórmula Ridge protegida. Mismo código que transportador.html línea 1810-1811.
function estimarPrecioRidge(km, kg, paradas, corredor) {
  km = parseInt(km) || 0;
  kg = parseInt(kg) || 0;
  paradas = parseInt(paradas) || 1;
  if (!km || !kg) return 0;
  const zonaAj = CORREDOR_A_AJUSTE[corredor] || '';
  const ajuste = CC_ZONA_AJUSTE[zonaAj] || 0;
  if (km < 50) {
    return Math.max(300000, 260000 + kg * 28 + 63186 * (paradas - 1));
  }
  return Math.max(950000,
    3097.69*km + 217.94*kg + 0.1215*km*kg
    - 1.0566*km*km - 0.0034*kg*kg
    + 63186*paradas + ajuste - 306248
  );
}

// Dado un texto libre devuelve el corredor, o null si no se puede canonizar
function corredorDe(texto) {
  if (!texto) return null;
  const canon = canonizarNodo(texto);
  if (!canon) return null;
  return CORREDORES[canon.toLowerCase()] || null;
}

/* -----------------------------------------------------------
 * canonizarNodo — dado un texto libre ("PPAL 3PL LA CARBONERA YUMBO"),
 * devuelve la ciudad canónica en mayúsculas sin tildes ("YUMBO").
 * Usado por "Agrupar por LogxIA" (tab Pedidos de control.html) y
 * futuras reglas de autopilot que necesiten reducir las N variantes
 * de una misma bodega a un solo nodo de consolidación.
 *
 * Estrategia: reutiliza getCoordenadas() que ya hace variantes +
 * substring match. Luego resuelve el nombre canónico buscando el
 * primer key del dict CIUDADES cuyas coords coinciden.
 * ----------------------------------------------------------- */
function canonizarNodo(texto) {
  if (!texto) return null;
  const coords = getCoordenadas(texto);
  if (!coords) return null;
  for (const [nombre, c] of Object.entries(CIUDADES)) {
    if (c[0] === coords[0] && c[1] === coords[1]) {
      return normalizarNombre(nombre).toUpperCase();
    }
  }
  return null;
}

/* -----------------------------------------------------------
 * Exposición explícita en window (defensive — con <script> normal
 * ya quedan globales, pero explicitar evita sorpresas si alguna
 * página cambia a type=module en el futuro).
 * ----------------------------------------------------------- */
window.CIUDADES         = CIUDADES;
window.geocodeCache     = geocodeCache;
window.GMAPS_KEY        = GMAPS_KEY;
window.normalizarNombre = normalizarNombre;
window.variantes        = variantes;
window.getCoordenadas   = getCoordenadas;
window.geocodeCiudad    = geocodeCiudad;
window.getCoords        = getCoords;
window.geo              = geo;
window.extraerCiudad    = extraerCiudad;
window.canonizarNodo    = canonizarNodo;
window.CORREDORES       = CORREDORES;
window.corredorDe       = corredorDe;
window.CC_ZONA_AJUSTE   = CC_ZONA_AJUSTE;
window.CORREDOR_A_AJUSTE = CORREDOR_A_AJUSTE;
window.estimarPrecioRidge = estimarPrecioRidge;
