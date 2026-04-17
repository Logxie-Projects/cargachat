-- ============================================================
-- TABLA: clientes
-- Propósito: configuración de cada cliente y su canal de ingesta
-- Un cliente puede tener múltiples canales (filas con mismo cliente_id padre)
-- ============================================================

CREATE TABLE clientes (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre           text NOT NULL,                -- 'AVGUST' | 'FATECO' | 'Cliente Nuevo'
  nit              text,
  email_contacto   text,
  nivel_ingesta    text NOT NULL                 -- ver CHECK abajo
                   CHECK (nivel_ingesta IN ('email', 'sheet', 'formulario', 'webhook')),
  -- Configuración nivel email
  email_origen     text,                         -- remitente autorizado: 'proyectos@avgust.com.co'
  email_subject    text,                         -- filtro subject opcional: 'SOLICITUD DE SERVICIOS'
  -- Configuración nivel sheet
  sheet_id         text,                         -- ID del Google Sheet del cliente
  sheet_tab        text,                         -- pestaña a leer
  sheet_col_map    jsonb,                         -- mapeo columnas: {"origen": "CIUDAD_ORIGEN", ...}
  -- Configuración nivel webhook
  webhook_secret   text,                         -- token de validación
  -- Configuración nivel formulario (no requiere config extra — usa Netfleet)
  activo           boolean NOT NULL DEFAULT true,
  notas            text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_clientes_nivel ON clientes(nivel_ingesta);
CREATE INDEX idx_clientes_email_origen ON clientes(email_origen) WHERE email_origen IS NOT NULL;

-- RLS
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;

-- Solo service_role puede leer/escribir clientes (nunca expuesto al frontend público)
CREATE POLICY "service_role_all" ON clientes
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================
-- DATOS INICIALES — clientes actuales
-- ============================================================

INSERT INTO clientes (nombre, nit, email_contacto, nivel_ingesta, email_origen, email_subject, notas)
VALUES
  ('AVGUST', NULL, 'proyectos@avgust.com.co', 'email',
   'proyectos@avgust.com.co', 'SOLICITUD DE SERVICIOS',
   'Cliente principal. Hoy usa AppSheet+Sheet. Futuro: webhook CRM directo.'),
  ('FATECO', NULL, 'proyectos@avgust.com.co', 'email',
   'proyectos@avgust.com.co', 'SOLICITUD DE SERVICIOS',
   'Filial de Avgust. Comparte canal de ingesta con AVGUST.');
