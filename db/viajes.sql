-- ============================================================
-- TABLA: viajes
-- Propósito: viaje consolidado — unidad de transporte asignada a un proveedor
-- Migra desde: Google Sheet ASIGNADOS
-- Columnas mapeadas desde ASIGNADOS real (export 2025-2026)
-- ============================================================

CREATE TABLE viajes_consolidados (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identificación
  viaje_ref           text NOT NULL UNIQUE,       -- 'RT-TOTAL-...' | 'JR41885' (ID_CONSOLIDADO)
  cliente_id          uuid REFERENCES clientes(id),

  -- Consolidación
  fecha_consolidacion timestamptz,               -- FECHA_CONSOLIDACION
  fecha_cargue        timestamptz,               -- fecha Carga
  empresa             text,                       -- EMPRESA_CONSOLIDADA: 'AVGUST'|'FATECO'|'AVGUST, FATECO'
  zona                text,                       -- ZONA_CONSOLIDADA: 'BOYACA'|'ORIENTE'|'EJE CAFETERO'
  origen              text,                       -- ORIGEN_CONSOLIDADO
  destino             text,                       -- DESTINO_CONSOLIDADO (texto libre, puede ser múltiple)
  cantidad_pedidos    int,                        -- CANTIDAD_PEDIDOS
  consecutivos        text,                       -- CONSECUTIVOS_INCLUIDOS — lista de pedido_ref separados por coma

  -- Logística
  km_total            numeric,                    -- KM_TOTAL
  flete_total         numeric,                    -- FLETE_TOTAL
  tipo_vehiculo       text,                       -- Tipo Vehiculo
  placa               text,                       -- Placa del Vehiculo
  conductor_nombre    text,                       -- Nombre del conductor
  conductor_id        text,                       -- Identificacion Conductor

  -- Carga
  peso_kg             numeric,                    -- PESO TRANSPORTADO (Kilos)
  contenedores        int NOT NULL DEFAULT 0,
  cajas               int NOT NULL DEFAULT 0,
  bidones             int NOT NULL DEFAULT 0,
  canecas             int NOT NULL DEFAULT 0,
  unidades_sueltas    int NOT NULL DEFAULT 0,
  valor_mercancia     numeric,                    -- VALOR DE LA MERCANCIA

  -- Costos adicionales
  candado             numeric NOT NULL DEFAULT 0,
  cargue_descargue    numeric NOT NULL DEFAULT 0,
  escolta             numeric NOT NULL DEFAULT 0,
  standby             numeric NOT NULL DEFAULT 0,
  itr                 numeric NOT NULL DEFAULT 0,
  otros               numeric NOT NULL DEFAULT 0,

  -- Proveedor
  proveedor           text,                       -- nombre empresa transportadora

  -- Estado
  estado              text NOT NULL DEFAULT 'pendiente'
                      CHECK (estado IN (
                        'pendiente',              -- consolidado, sin confirmar proveedor
                        'confirmado',             -- proveedor aceptó
                        'en_ruta',                -- vehículo en movimiento
                        'entregado',              -- entrega completada
                        'finalizado',             -- cumplidos recibidos, cerrado
                        'cancelado'
                      )),

  -- Soportes y documentos
  foto_cargue         text,                       -- URL
  soporte_entrega     text,                       -- URL
  confirma_vehiculo   text,

  -- Metadatos
  fuente              text NOT NULL DEFAULT 'sheet_asignados'
                      CHECK (fuente IN ('sheet_asignados', 'netfleet', 'webhook', 'manual')),
  observaciones       text,
  raw_payload         text,                       -- JSON/texto original para auditoría
  mes                 int,
  anio                int,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_viajes_cliente ON viajes_consolidados(cliente_id);
CREATE INDEX idx_viajes_estado ON viajes_consolidados(estado);
CREATE INDEX idx_viajes_fecha_cargue ON viajes_consolidados(fecha_cargue);
CREATE INDEX idx_viajes_zona ON viajes_consolidados(zona);
CREATE INDEX idx_viajes_mes_anio ON viajes_consolidados(anio, mes);

-- Trigger updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER viajes_updated_at
  BEFORE UPDATE ON viajes_consolidados
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE viajes_consolidados ENABLE ROW LEVEL SECURITY;

-- Anon puede SELECT viajes en estado públicos (para netfleet.app mapa)
CREATE POLICY "anon_select_publicos" ON viajes_consolidados
  FOR SELECT TO anon
  USING (estado IN ('pendiente', 'confirmado'));

-- Service role acceso total
CREATE POLICY "service_role_all" ON viajes_consolidados
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Authenticated (transportadores/admin) acceso total
CREATE POLICY "authenticated_all" ON viajes_consolidados
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
