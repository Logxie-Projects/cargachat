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

// Detectar zona
const esHub = zonaHub.some(b => origenNorm.includes(b)) &&
  destinosNorm.every(d => zonaHub.some(b => d.includes(b)));

const esBuenaventura =
  (zonaHub.some(b => origenNorm.includes(b)) &&
    destinosNorm.some(d => zonaBuenaventura.some(b => d.includes(b)))) ||
  zonaBuenaventura.some(b => origenNorm.includes(b));

const esEjeCafetero = !esHub && destinosNorm.some(d =>
  zonaEjeCafetero.some(e => d.includes(e)));

const esNorte = !esHub && km > 800 && destinosNorm.some(d =>
  zonaNorte.some(n => d.includes(n)));

const esLlanos = !esHub && destinosNorm.some(d =>
  zonaLlanos.some(l => d.includes(l)));

const esSur = !esHub && destinosNorm.some(d =>
  zonaSur.some(s => d.includes(s)));

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
let zona_detectada = 'General';

if (esBuenaventura) {
  zona_detectada = 'Buenaventura';
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
  let factor_zona;

  if (esHub) {
    zona_detectada = 'Hub';
    factor_zona = 0.85;
  } else if (esEjeCafetero) {
    zona_detectada = 'Eje Cafetero';
    factor_zona = 1.10;
  } else if (esNorte) {
    zona_detectada = 'Norte';
    factor_zona = 1.15;
  } else if (esLlanos) {
    zona_detectada = 'Llanos';
    factor_zona = 1.25;
  } else if (esSur) {
    zona_detectada = 'Sur';
    factor_zona = 1.05;
  } else {
    zona_detectada = 'General';
    factor_zona = 1.00;
  }

  const precio_formula = ((3016 * km) + (156 * peso) + 100469) * factor_zona;
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
    precio_base: Math.round(precio_base),
    zona_detectada,
    valor_mercancia_pesos: Math.round(valor_mercancia_pesos)
  }
}];