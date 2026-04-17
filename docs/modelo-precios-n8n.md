const datos = $('Code in JavaScript2').item.json;
const response = $json;

// Extraer distancia y tiempo
let km = 0;
let numParadas = 0;
let minutosMaximo = 0;

const rows = response.rows?.[0]?.elements || [];

rows.forEach(el => {
  if (el.status === 'OK') {
    numParadas++;
    const kmActual = Math.round(el.distance.value / 1000);
    const minutosActual = Math.round(el.duration.value / 60);
    if (kmActual > km) {
      km = kmActual;
      minutosMaximo = minutosActual;
    }
  }
});

// Duración con 1 hora por parada
const minutosTotal = minutosMaximo + (numParadas * 60);
const horasTotal = Math.floor(minutosTotal / 60);
const minsResto = minutosTotal % 60;
const duracion = horasTotal > 0
  ? `${horasTotal}h${minsResto > 0 ? ' ' + minsResto + 'min' : ''}`
  : `${minsResto}min`;

const peso = parseFloat(datos.peso_kg) || 0;
const paradasCap = Math.min(numParadas, 10); // modelo entrenado hasta 10

const origenNorm = (datos.origen || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const destinosNorm = (datos.destino || '').split(',').map(d =>
  d.trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
);

// Zonas
const zonaHub          = ['funza', 'yumbo', 'espinal'];
const zonaEjeCafetero  = ['virginia', 'cartago', 'armenia', 'manizales', 'santa rosa', 'chinchina', 'pereira', 'dosquebradas', 'la virginia', 'calarca', 'montenegro', 'quimbaya', 'belalcazar'];
const zonaNorte        = ['monteria', 'valledupar', 'barranquilla', 'cartagena', 'santa marta', 'sincelejo', 'riohacha', 'lorica', 'cerete', 'magangue', 'mompox', 'el banco', 'aguachica'];
const zonaLlanos       = ['villavicencio', 'yopal', 'arauca', 'acacias', 'granada', 'puerto lopez', 'restrepo', 'cumaral', 'aguazul', 'tauramena', 'trinidad', 'paz de ariporo', 'orocue', 'san martin'];
const zonaSur          = ['pasto', 'ipiales', 'tumaco', 'popayan', 'mocoa', 'el tigre', 'puerto asis', 'orito', 'la hormiga', 'sibundoy', 'villagarzon', 'santander de quilichao', 'miranda', 'patia', 'florencia', 'belen de los andaquies'];
const zonaBuenaventura = ['buenaventura'];
const zonaAntioquia    = ['medellin', 'rionegro', 'envigado', 'itagui', 'bello', 'sabaneta', 'la ceja', 'marinilla', 'guarne', 'caucasia', 'apartado', 'turbo'];
const zonaBoyaca       = ['tunja', 'duitama', 'sogamoso', 'chiquinquira', 'paipa', 'villa de leyva', 'samaca', 'ventaquemada', 'tibasosa', 'nobsa'];
const zonaCentro       = ['ibague', 'girardot', 'melgar', 'honda', 'mariquita', 'flandes', 'guamo'];
const zonaCundinamarca = ['zipaquira', 'chia', 'facatativa', 'soacha', 'mosquera', 'madrid', 'cajica', 'cota', 'tenjo', 'tabio', 'la calera', 'fusagasuga', 'silvania', 'tocancipa'];
const zonaOccidente    = ['cali', 'palmira', 'buga', 'tulua', 'sevilla', 'buenaventura', 'jamundi', 'candelaria', 'ginebra', 'el cerrito', 'dagua', 'la union'];
const zonaSantanderes  = ['bucaramanga', 'cucuta', 'giron', 'floridablanca', 'piedecuesta', 'san gil', 'barrancabermeja', 'pamplona', 'ocana', 'los patios'];
const zonaTolhuil      = ['neiva', 'garzon', 'pitalito', 'campoalegre', 'la plata', 'san agustin', 'espinal', 'natagaima', 'purificacion'];
const zonaValle        = ['cali', 'palmira', 'buga', 'tulua', 'yumbo', 'jamundi', 'candelaria', 'ginebra', 'cartago', 'la union'];
const zonaOriente      = ['bucaramanga', 'cucuta', 'giron', 'floridablanca', 'piedecuesta', 'pamplona'];

// Detectar zona especial
const esHub = zonaHub.some(b => origenNorm.includes(b)) &&
  destinosNorm.every(d => zonaHub.some(b => d.includes(b)));

const esBuenaventura =
  (zonaHub.some(b => origenNorm.includes(b)) &&
    destinosNorm.some(d => zonaBuenaventura.some(b => d.includes(b)))) ||
  zonaBuenaventura.some(b => origenNorm.includes(b));

// Ajustes de zona del modelo ML (Ridge, n=1.015 viajes reales)
// Cada valor es un ajuste aditivo en COP entrenado con datos reales
const ZONA_AJUSTES = {
  'Antioquia':    15759,
  'Boyacá':       87756,
  'Centro':       22045,
  'Cundinamarca': 65602,
  'Eje Cafetero': -18794,
  'Llanos':       159210,
  'Occidente':    10720,
  'Oriente':      -176447,
  'Santanderes':  -213483,
  'Tolima/Huila': -18146,
  'Valle':        34226,
  'Norte':        79189,  // usa ajuste "OTRA" del modelo
  'Sur':          79189,
  'Hub':          0,
};

// Detectar zona por destino
let zona_detectada = 'General';
let ajusteZona = 0;

if (esBuenaventura) {
  zona_detectada = 'Buenaventura';
} else if (esHub) {
  zona_detectada = 'Hub';
  ajusteZona = ZONA_AJUSTES['Hub'];
} else if (destinosNorm.some(d => zonaLlanos.some(l => d.includes(l)))) {
  zona_detectada = 'Llanos';
  ajusteZona = ZONA_AJUSTES['Llanos'];
} else if (destinosNorm.some(d => zonaBoyaca.some(b => d.includes(b)))) {
  zona_detectada = 'Boyacá';
  ajusteZona = ZONA_AJUSTES['Boyacá'];
} else if (destinosNorm.some(d => zonaSantanderes.some(s => d.includes(s)))) {
  zona_detectada = 'Santanderes';
  ajusteZona = ZONA_AJUSTES['Santanderes'];
} else if (destinosNorm.some(d => zonaOriente.some(o => d.includes(o)))) {
  zona_detectada = 'Oriente';
  ajusteZona = ZONA_AJUSTES['Oriente'];
} else if (destinosNorm.some(d => zonaCundinamarca.some(c => d.includes(c)))) {
  zona_detectada = 'Cundinamarca';
  ajusteZona = ZONA_AJUSTES['Cundinamarca'];
} else if (destinosNorm.some(d => zonaEjeCafetero.some(e => d.includes(e)))) {
  zona_detectada = 'Eje Cafetero';
  ajusteZona = ZONA_AJUSTES['Eje Cafetero'];
} else if (destinosNorm.some(d => zonaValle.some(v => d.includes(v)))) {
  zona_detectada = 'Valle';
  ajusteZona = ZONA_AJUSTES['Valle'];
} else if (destinosNorm.some(d => zonaAntioquia.some(a => d.includes(a)))) {
  zona_detectada = 'Antioquia';
  ajusteZona = ZONA_AJUSTES['Antioquia'];
} else if (destinosNorm.some(d => zonaCentro.some(c => d.includes(c)))) {
  zona_detectada = 'Centro';
  ajusteZona = ZONA_AJUSTES['Centro'];
} else if (destinosNorm.some(d => zonaTolhuil.some(t => d.includes(t)))) {
  zona_detectada = 'Tolima/Huila';
  ajusteZona = ZONA_AJUSTES['Tolima/Huila'];
} else if (destinosNorm.some(d => zonaOccidente.some(o => d.includes(o)))) {
  zona_detectada = 'Occidente';
  ajusteZona = ZONA_AJUSTES['Occidente'];
} else if (km > 800 && destinosNorm.some(d => zonaNorte.some(n => d.includes(n)))) {
  zona_detectada = 'Norte';
  ajusteZona = ZONA_AJUSTES['Norte'];
} else if (destinosNorm.some(d => zonaSur.some(s => d.includes(s)))) {
  zona_detectada = 'Sur';
  ajusteZona = ZONA_AJUSTES['Sur'];
}

// Valor mercancía en pesos
const TRM = 3700;
const valor_mercancia_raw = parseFloat(
  (datos.valor_mercancia || '0').replace(/\./g, '').replace(',', '.')
) || 0;
const valor_mercancia_pesos = esBuenaventura
  ? valor_mercancia_raw * TRM
  : valor_mercancia_raw;

// Precio
const precio_minimo_absoluto = 950000;
let precio_base = 0;

if (esBuenaventura) {
  // Precios fijos para Buenaventura (sin cambio)
  if (destinosNorm.some(d => d.includes('funza')) || origenNorm.includes('funza')) {
    precio_base = 7000000;
  } else if (destinosNorm.some(d => d.includes('espinal')) || origenNorm.includes('espinal')) {
    precio_base = 6000000;
  } else if (destinosNorm.some(d => d.includes('yumbo')) || origenNorm.includes('yumbo')) {
    precio_base = 3000000;
  } else {
    precio_base = 5000000;
  }
} else {
  // Modelo ML polinomial grado 2 + paradas + zona (Ridge, R²=0.919, n=1.015 viajes)
  const precio_formula = Math.max(0,
    3097.69 * km
    + 217.94 * peso
    + 0.1215 * km * peso
    - 1.0566 * km * km
    - 0.0034 * peso * peso
    + 63186 * paradasCap
    + ajusteZona
    - 306248
  );

  const techo = valor_mercancia_pesos * 0.028;

  if (techo > precio_minimo_absoluto) {
    precio_base = Math.min(precio_formula, techo);
  } else {
    precio_base = precio_formula;
  }

  precio_base = Math.max(precio_base, precio_minimo_absoluto);
}

return [{
  json: {
    ...datos,
    km_reales: km,
    duracion_estimada: duracion,
    num_paradas: numParadas,
    precio_base: Math.round(precio_base),
    zona_detectada,
    valor_mercancia_pesos: Math.round(valor_mercancia_pesos)
  }
}];
