# LogxIA — Agente IA Operativo

Automatizaciones n8n que conforman el agente LogxIA para la operación Avgust/Fateco.  
n8n self-hosted: `https://n8n.srv1173119.hstgr.cloud`

---

## Workflows activos en producción

### 1. LogxIA — Parser Detalle Pedidos
**Archivo:** `workflows/LogxIA_Parser_Detalle_Pedidos.json`  
**Nombre en n8n:** `LogxIA — PRODUCCIÓN v2 (Mails Avgust)` *(pendiente renombrar)*  
**Trigger:** Gmail — subject `SOLICITUD DE SERVICIOS` desde `proyectos@avgust.com.co`

**Flujo:**
```
Gmail Trigger → HTTP (leer body completo base64) → Parsear Detalle Pedidos v2 → Escribir DETALLE_PEDIDOS (Sheet)
```

**Output por pedido** → Sheet `DETALLE_PEDIDOS` (`gid=749562420`):
`VIAJE_ID, REMISION, EMPRESA, ZONA, ORIGEN, DESTINO, PESO_KG, VALOR_MERCANCIA, DIAS_ATENCION, V1_DESDE/HASTA, V2_DESDE/HASTA, HORARIO_SABADO, CLIENTE, CONTACTO, TELEFONO, DIRECCION, NOTAS, LLAMAR_ANTES`

**Fix clave:** `.replace(/\*/g, '')` normaliza mails reenviados con asteriscos (formato HTML→texto).  
**Credenciales n8n:** Gmail `wwd5v7WrftObobuR` · Sheets `IuCNLIa09oW4ZWBu`  
**Consumidor:** `analizador-rutas.html`

---

### 2. LogxIA — Bot Telegram Conversacional
**Archivo:** `workflows/LogxIA_Bot_Telegram.json`  
**Trigger:** Telegram webhook

**Flujo:**
```
Telegram Trigger → Validar Usuario → Ejecutar Lector de Pedidos → Resolver Consulta
  → Necesita Claude? 
      Sí → Llamar Claude API → Procesar Respuesta
      No → Procesar Respuesta
  → IF Notificar Proveedor?
      Sí → Preparar Emails → Enviar Email Urgente
  → Responder Telegram
```

**Roles:** `admin` (Bernardo) · `proveedor` (transportadores por Telegram ID)  
**Capacidades:** consultas de estado de pedidos, alertas urgentes, notificación a proveedores vía email  
**⚠️ Post-importación:** poblar `ADMIN_IDS` y los arrays de IDs por proveedor en nodo `Validar Usuario`

---

### 3. AvgustIA — Lector de Pedidos *(subworkflow)*
**Archivo:** `workflows/AvgustIA_Lector_de_Pedidos.json`  
**Trigger:** Manual o Schedule cada 4h (no necesita estar activo — lo invocan otros workflows)

**Flujo:**
```
Manual/Schedule → Leer Google Sheet ("Datos desde Unificada") → Filtrar Mes Actual → Estructurar y Resumir Pedidos → Set Output Final
```

**Fuente:** Sheet `Seguimiento y Cumplidos` → pestaña `Datos desde Unificada`  
**Sheet ID:** `1hh9suCr1KkGDJekAMul3kYdi74MRD0778kcZ-Vl1tWQ`

**Output:**
```json
{
  "totalPedidos": 0,
  "pedidosSinEstado": 0,
  "pedidosPendientes": 0,
  "pedidosConNovedad": 0,
  "pedidosRechazados": 0,
  "pedidosEntregadosOK": 0,
  "listaPedidos": []
}
```

**Estados válidos:** `Pendiente` · `Entregado OK` · `Entregado con Novedad` · `Rechazado por Cliente` · vacío = sin reporte

---

### 4. AvgustIA — Seguimiento a Transportadores
**Archivo:** `workflows/AvgustIA_Seguimiento_Transportadores.json`  
**Trigger:** Schedule `0 6,12,18 * * *` (6am / 12pm / 6pm)

**Flujo:**
```
Schedule → Ejecutar Lector de Pedidos → Filtrar y Agrupar por Proveedor → Generar Email por Proveedor → Enviar Email (Gmail)
```

**Lógica:** filtra pedidos con estado vacío o `Pendiente`, agrupa por proveedor, envía email HTML con tabla de pendientes.  
**CC siempre:** `bernardojaristizabal@gmail.com, proyectos@avgust.com.co`

**Proveedores configurados:**
| Clave exacta en Sheet | Email TO |
|---|---|
| `PRACARGO` | despachos@pracargo.com |
| `ENTRAPETROL` | gerencia@stentrapetrol.com |
| `TRASAMER S.A.S` | trasamergerencia@gmail.com |
| `LOGISTICA Y SERVICIOS JR S.A.S` | comercial1jrlogistic@gmail.com |
| `TRANSPORTE NUEVA COLOMBIA` | despachoscali2@transnuevacolombia.com |

**⚠️ Faltantes:** Vigía y Global Logística no están configurados → sus pedidos llegan solo a internos con asunto `[SIN CORREO CONFIGURADO]`

**⚠️ Post-importación:** en nodo `Ejecutar Lector de Pedidos`, seleccionar manualmente `AvgustIA - Lector de Pedidos` en el desplegable de workflows.

---

## Instrucciones de importación en n8n

1. Ir a `https://n8n.srv1173119.hstgr.cloud`
2. **Importar primero** `AvgustIA_Lector_de_Pedidos.json` (es subworkflow, los demás dependen de él)
3. Importar los restantes en cualquier orden
4. En cada workflow que tenga nodo `Ejecutar Lector de Pedidos`: abrir el nodo y seleccionar `AvgustIA - Lector de Pedidos` en el campo Workflow
5. Reconectar credenciales Gmail y Google Sheets (los IDs quedan vacíos al exportar)
6. Activar solo los workflows que deben correr en producción (Seguimiento y Parser)

---

## Pendientes LogxIA

- [ ] Renombrar `LogxIA — PRODUCCIÓN v2 (Mails Avgust)` → `LogxIA — Parser Detalle Pedidos` en n8n
- [ ] Agregar Vigía y Global Logística al diccionario `CORREOS_PROVEEDORES` en Seguimiento
- [ ] Poblar `ADMIN_IDS` y arrays de IDs de Telegram por proveedor en Bot
- [ ] **Módulo 3:** Consolidación inteligente
- [ ] **Módulo 4:** Pricing dinámico
- [ ] **Módulo 5:** Predicción de demanda
