-- ============================================================
-- TABLA: pedidos
-- Propósito: pedido individual — unidad de entrega a un cliente final
-- Migra desde: Google Sheet Base_inicio-def
-- Columnas mapeadas desde Base_inicio-def real (export 2025-2026)
-- ============================================================

CREATE TABLE pedidos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Relaciones
  viaje_id         uuid REFERENCES viajes_consolidados(id),   -- NULL hasta que Bernardo consolida
  cliente_id       uuid REFERENCES clientes(id),               -- Nullable temporalmente para migración histórica
                                                                -- Backfill post-migración desde empresa, luego ALTER TABLE ... SET NOT NULL

  -- Campos mínimos obligatorios (cualquier fuente puede proveerlos)
  origen           text NOT NULL,
  destino          text NOT NULL,
  fuente           text NOT NULL
                   CHECK (fuente IN ('email', 'sheet', 'formulario', 'webhook')),

  -- Identificación (fuentes estructuradas)
  pedido_ref       text,                          -- 'RM-00004430' | 'TIT-1280' | NULL si email libre
  id_consecutivo   text,                          -- 'RT-0002' (ID interno AppSheet — legacy)

  -- Clasificación
  empresa          text,                          -- 'AVGUST' | 'FATECO'
  zona             text,                          -- 'BOYACA' | 'ORIENTE' | 'EJE CAFETERO'
  motivo_viaje     text,                          -- 'Venta' | 'Devolución' | 'Muestra'
  prioridad        text,                          -- 'Baja - 48 h' | 'Alta - 24 h'

  -- Fechas
  fecha_cargue     timestamptz,                   -- FECHA ESTIMADA CARGUE
  fecha_entrega    timestamptz,                   -- FECHA REQUERIDA DE ENTREGA

  -- Carga
  peso_kg          numeric,
  tipo_mercancia   text,
  contenedores     int NOT NULL DEFAULT 0,
  cajas            int NOT NULL DEFAULT 0,
  bidones          int NOT NULL DEFAULT 0,
  canecas          int NOT NULL DEFAULT 0,
  unidades_sueltas int NOT NULL DEFAULT 0,
  valor_mercancia  numeric,                       -- VALOR DE LA MERCANCIA
  valor_factura    numeric,                       -- VALOR DE LA FACTURA

  -- Transporte
  tipo_vehiculo    text,
  flete            numeric NOT NULL DEFAULT 0,
  standby          numeric NOT NULL DEFAULT 0,
  candado          numeric NOT NULL DEFAULT 0,
  escolta          numeric NOT NULL DEFAULT 0,
  itr              numeric NOT NULL DEFAULT 0,
  cargue_descargue text,                          -- 'Cargue' | 'Descargue' | 'Ambos'
  proveedor        text,

  -- Destino / receptor
  cliente_nombre   text,                          -- CLIENTE (nombre del cliente final)
  contacto_nombre  text,
  contacto_tel     text,                          -- WHATSAPP
  direccion        text,                          -- Dirrecion
  horario          text,                          -- horario de recibo (texto libre)
  llamar_antes     boolean NOT NULL DEFAULT false,
  observaciones    text,                          -- Observaciones

  -- Gestión interna Logxie
  vendedor         text,                          -- VENDEDOR QUE SOLICITA
  jefe_zona        text,                          -- JEFE DE ZONA
  coordinador      text,                          -- COORDINADOR DEL SERVICIO
  placa            text,                          -- PLACA

  -- Estado
  estado           text NOT NULL DEFAULT 'sin_consolidar'
                   CHECK (estado IN (
                     'sin_consolidar',            -- en Base_inicio-def, esperando consolidación
                     'consolidado',               -- incluido en un viaje (viaje_id NOT NULL)
                     'asignado',                  -- proveedor confirmado
                     'en_ruta',
                     'entregado',
                     'entregado_novedad',         -- entregado con novedad
                     'rechazado',                 -- rechazado por cliente
                     'cancelado'
                   )),
  estado_original  text,                          -- estado crudo del Sheet Base_inicio-def antes de normalizar ('EN PROCESO', 'EJECUTADO', etc.)

  -- Soportes
  soporte_1        text,
  soporte_2        text,
  soporte_3        text,
  confirma_vehiculo text,
  bodega_email     text,
  nro_factura_proveedor text,

  -- Auditoría
  raw_payload      text,                          -- texto/JSON original tal como llegó
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_pedidos_viaje ON pedidos(viaje_id) WHERE viaje_id IS NOT NULL;
CREATE INDEX idx_pedidos_cliente ON pedidos(cliente_id);
CREATE INDEX idx_pedidos_estado ON pedidos(estado);
CREATE INDEX idx_pedidos_fecha_cargue ON pedidos(fecha_cargue);
CREATE INDEX idx_pedidos_zona ON pedidos(zona);
CREATE INDEX idx_pedidos_ref ON pedidos(pedido_ref) WHERE pedido_ref IS NOT NULL;
-- Índice de lookup (cliente_id, pedido_ref). NO es unique porque la data legacy
-- del Sheet Base_inicio-def tiene pedido_refs duplicados (re-entradas legítimas:
-- pedidos cancelados y recreados, correcciones, reclamaciones).
-- Si se necesita prevenir duplicados en parsers nuevos, aplicar dedup en la capa
-- de ingesta (n8n) con reglas de negocio específicas.
CREATE INDEX idx_pedidos_ref_cliente ON pedidos(cliente_id, pedido_ref)
  WHERE pedido_ref IS NOT NULL;

-- Trigger updated_at
CREATE TRIGGER pedidos_updated_at
  BEFORE UPDATE ON pedidos
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
-- NOTA: update_updated_at() ya fue creada en viajes.sql — ejecutar viajes.sql primero

-- RLS
ALTER TABLE pedidos ENABLE ROW LEVEL SECURITY;

-- Anon NO puede ver pedidos (datos operativos internos)
-- Authenticated y service_role acceso total
CREATE POLICY "service_role_all" ON pedidos
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "authenticated_all" ON pedidos
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
