-- ─────────────────────────────────────────────────────────
-- zonas_umbrales — umbrales per-zona usados por LogxIA para
-- sugerir consolidación "por servicio al cliente" aunque no
-- se alcance la meta universal de 4.000 kg. Seed inicial con
-- los 2 casos que Bernardo confirmó; el resto se completa
-- iterativamente conforme aprendemos de su operación.
-- ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS zonas_umbrales (
  zona           TEXT PRIMARY KEY,            -- BOYACÁ, EJE CAFETERO, VALLE, …
  min_pedidos    INT,                          -- N pedidos mínimos para despachar por servicio
  min_flete_pct  NUMERIC DEFAULT 3,            -- tope % flete/valor mercancía (señal B económica)
  notas          TEXT,
  updated_at     TIMESTAMPTZ DEFAULT now(),
  updated_by     UUID REFERENCES auth.users(id)
);

-- Seed de umbrales conocidos (Bernardo 2026-04-23)
INSERT INTO zonas_umbrales (zona, min_pedidos, notas) VALUES
  ('BOYACÁ',       10, 'Funza → Boyacá: ruta con muchas paradas rurales, umbral alto'),
  ('EJE CAFETERO',  5, 'Yumbo → Armenia/Pereira/Manizales, volumen medio')
ON CONFLICT (zona) DO UPDATE SET
  min_pedidos = EXCLUDED.min_pedidos,
  notas       = EXCLUDED.notas,
  updated_at  = now();

-- RLS: staff lee/escribe todo; resto denegado
ALTER TABLE zonas_umbrales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS zonas_umbrales_staff ON zonas_umbrales;
CREATE POLICY zonas_umbrales_staff ON zonas_umbrales
  FOR ALL TO authenticated
  USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

DROP POLICY IF EXISTS zonas_umbrales_service_role ON zonas_umbrales;
CREATE POLICY zonas_umbrales_service_role ON zonas_umbrales
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Verificación
SELECT zona, min_pedidos, min_flete_pct, notas FROM zonas_umbrales ORDER BY zona;
