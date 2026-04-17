# Workflow n8n — Check de Ruta → Google Sheet + Email

Este documento describe el workflow que debes armar en n8n para recibir los reportes de `checkderuta.html` y:

1. Guardar / actualizar una pestaña por viaje en un **Google Sheet maestro**
2. Enviar un **correo de actualización** a los destinatarios del viaje

---

## 1. Trigger: Webhook

**Nodo:** `Webhook`

- **HTTP Method:** `POST`
- **Path:** `checkderuta` (la URL queda como `https://n8n.tu-dominio.com/webhook/checkderuta`)
- **Response Mode:** `Last Node` (para devolver el `sheet_url` al frontend)
- **Response Data:** `All Entries`

El frontend envía un JSON con esta estructura:

```json
{
  "tripId": "VJ-2026-000123",
  "fecha_plan": "2026-04-16",
  "origen": "Funza",
  "origen_lat": 4.7132,
  "origen_lng": -74.1966,
  "km_plan": 420,
  "destinatarios": ["juan@empresa.com", "maria@empresa.com"],
  "cargue": {
    "fecha_real": "2026-04-16",
    "hora_real": "06:15"
  },
  "ejecucion": [
    {
      "exec_order": 1,
      "plan_order": 1,
      "reordenado": false,
      "destino": "Sogamoso",
      "lat": 5.7150, "lng": -72.9267,
      "plan_time": "10:30 AM",
      "plan_km": 210,
      "real_fecha": "2026-04-16",
      "real_hora": "10:45",
      "estado": "entregado",
      "novedad": ""
    },
    {
      "exec_order": 2,
      "plan_order": 3,
      "reordenado": true,
      "destino": "Duitama",
      "lat": 5.8281, "lng": -73.0297,
      "plan_time": "12:15 PM",
      "plan_km": 245,
      "real_fecha": "2026-04-16",
      "real_hora": "13:02",
      "estado": "entregado",
      "novedad": "Cliente pidió esperar 20 min"
    }
  ],
  "resumen": {
    "entregas_ok": 2,
    "entregas_total": 3,
    "no_entregados": 0,
    "novedades": 1,
    "orden_cumplido": false
  },
  "sheet_url_previo": "",
  "reportado_en": "2026-04-16T14:30:00.000Z"
}
```

---

## 2. Crear o ubicar la pestaña del viaje

**Nodo:** `Google Sheets` → operación `Read` o `Append`

- **Spreadsheet ID:** el ID del Sheet maestro (creá uno dedicado: "NETFLEET — Check de Rutas")
- **Sheet name:** `={{$json.tripId}}` (cada viaje tiene su propia pestaña)

### Opción simple: crear tab si no existe

Usar el nodo `Google Sheets → Sheet → Create` con error passthrough (si ya existe, ignorar error).

Luego en el mismo workflow agregar un nodo **Google Sheets → Row → Append or Update** que escriba:

**Fila de encabezado (escribir solo una vez):**
| tripId | fecha_plan | origen | km_plan | reportado_en |

**Filas de ejecución (una por destino):**
| exec_order | plan_order | reordenado | destino | plan_time | plan_km | real_fecha | real_hora | estado | novedad |

> Tip: usa un "Split In Batches" o "Item Lists → Split Out" sobre `ejecucion` para escribir una fila por destino.

---

## 3. Construir el cuerpo del correo

**Nodo:** `Code` (JavaScript) para armar el HTML del correo:

```js
const d = $input.first().json;
const rows = d.ejecucion.map(e => {
  const emoji = {entregado:'✅',parcial:'🟡',no_entregado:'❌',cliente_cerrado:'🚪',reprogramado:'⏳',pendiente:'⚪'}[e.estado] || '⚪';
  const reorden = e.reordenado ? ` <span style="color:#E89B20">(plan #${e.plan_order})</span>` : '';
  const nov = e.novedad ? `<br><small style="color:#666">📝 ${e.novedad}</small>` : '';
  return `<tr>
    <td style="padding:6px 10px;border-bottom:1px solid #eee">#${e.exec_order}${reorden}</td>
    <td style="padding:6px 10px;border-bottom:1px solid #eee"><strong>${e.destino}</strong>${nov}</td>
    <td style="padding:6px 10px;border-bottom:1px solid #eee">${e.plan_time||'—'}</td>
    <td style="padding:6px 10px;border-bottom:1px solid #eee">${e.real_hora||'—'}</td>
    <td style="padding:6px 10px;border-bottom:1px solid #eee">${emoji} ${e.estado}</td>
  </tr>`;
}).join('');

const html = `
<div style="font-family:Arial,sans-serif;max-width:720px;margin:0 auto">
  <div style="background:#0E1B4D;color:#fff;padding:16px 20px">
    <h2 style="margin:0;font-size:18px">LogxIA — Check de Ruta ${d.tripId}</h2>
    <p style="margin:4px 0 0;font-size:13px;opacity:.8">Actualización del viaje · ${new Date(d.reportado_en).toLocaleString('es-CO')}</p>
  </div>
  <div style="padding:16px 20px;background:#F5F6FA">
    <p><strong>Origen:</strong> ${d.origen} · <strong>Km plan:</strong> ${d.km_plan} · <strong>Fecha:</strong> ${d.fecha_plan}</p>
    <div style="display:flex;gap:8px;margin:12px 0">
      <div style="flex:1;background:#fff;padding:10px;border-radius:6px;text-align:center">
        <div style="font-size:11px;color:#666">Entregas</div>
        <div style="font-size:18px;font-weight:600">${d.resumen.entregas_ok}/${d.resumen.entregas_total}</div>
      </div>
      <div style="flex:1;background:#fff;padding:10px;border-radius:6px;text-align:center">
        <div style="font-size:11px;color:#666">Orden</div>
        <div style="font-size:14px;font-weight:600;color:${d.resumen.orden_cumplido?'#22c55e':'#E89B20'}">${d.resumen.orden_cumplido?'✅ Cumplido':'⚠ Alterado'}</div>
      </div>
      <div style="flex:1;background:#fff;padding:10px;border-radius:6px;text-align:center">
        <div style="font-size:11px;color:#666">Novedades</div>
        <div style="font-size:18px;font-weight:600">${d.resumen.novedades}</div>
      </div>
    </div>
    <table style="width:100%;border-collapse:collapse;background:#fff;border-radius:6px;overflow:hidden;font-size:12px">
      <thead>
        <tr style="background:#00BFDF;color:#0E1B4D">
          <th style="padding:8px 10px;text-align:left">Orden</th>
          <th style="padding:8px 10px;text-align:left">Destino</th>
          <th style="padding:8px 10px;text-align:left">Plan</th>
          <th style="padding:8px 10px;text-align:left">Real</th>
          <th style="padding:8px 10px;text-align:left">Estado</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
    <p style="margin-top:16px;font-size:12px;color:#666">
      Ver detalle en el Google Sheet del viaje: <a href="{{SHEET_URL}}">Abrir Sheet</a>
    </p>
  </div>
</div>`;

return { html, subject: `[LogxIA] ${d.tripId} — ${d.resumen.entregas_ok}/${d.resumen.entregas_total} entregas`, to: d.destinatarios.join(',') };
```

Reemplaza `{{SHEET_URL}}` con la URL del Sheet (del paso anterior).

---

## 4. Enviar correo

**Nodo:** `Gmail` (o `Send Email` con SMTP)

- **Resource:** `Message`
- **Operation:** `Send`
- **To:** `={{$json.to}}`
- **Subject:** `={{$json.subject}}`
- **Email Type:** `HTML`
- **HTML Content:** `={{$json.html}}`

---

## 5. Respuesta al frontend

**Nodo:** `Respond to Webhook`

- **Respond With:** `JSON`
- **Response Body:**
```json
{
  "sheet_url": "{{URL_DEL_SHEET}}",
  "mail_sent": true,
  "recipients": {{$json.destinatarios}}
}
```

El frontend lee `sheet_url` y lo guarda en localStorage para mostrar el botón "📊 Abrir Sheet".

---

## 6. Configuración en el frontend

Una vez desplegado el workflow:

1. Copiá la **URL del webhook de producción** en n8n (algo como `https://n8n.logxie.com/webhook/checkderuta`)
2. En `checkderuta.html`, abrí **⚙ Configuración webhook n8n** y pegá la URL
3. La URL se guarda en localStorage global (sirve para todos los viajes)
4. Los correos se guardan por `tripId` (cada viaje recuerda sus destinatarios)

---

## Opciones futuras

- **Slack** en vez de correo
- **WhatsApp** vía Twilio / WhatsApp Cloud API
- **Dashboard** con resumen de todos los viajes especiales
- **Alerta automática** si hay >30min de delay o >2 no entregados
- Disparar notificación automática al transportador si se detecta alteración del orden
