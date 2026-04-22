-- ═══════════════════════════════════════════════════════════════
-- SCENARIOS DE VIAJE — capa de trabajo tentativa para el operador
-- Un scenario agrupa pedidos sin comprometerlos. Un pedido puede
-- estar en N scenarios mientras siga sin_consolidar. Al promover
-- un scenario, los otros que compartían pedidos se marcan
-- 'conflictivo' para limpieza manual (workflow confirmado 2026-04-22).
-- ═══════════════════════════════════════════════════════════════

-- ───── Tablas ─────
CREATE TABLE IF NOT EXISTS scenarios_viaje (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre                text NOT NULL,
  descripcion           text,
  estado                text NOT NULL DEFAULT 'borrador'
                        CHECK (estado IN ('borrador','promovido','descartado','conflictivo','invalidado')),
  peso_kg_total         numeric DEFAULT 0,
  valor_mercancia_total numeric DEFAULT 0,
  cantidad_pedidos      int DEFAULT 0,
  flete_estimado        numeric,
  km_estimado           numeric,
  ruta_orden            jsonb,
  origen_sugerido       text,
  destinos_sugeridos    text,
  zonas                 text[],
  promovido_a_viaje_id  uuid REFERENCES viajes_consolidados(id),
  promovido_at          timestamptz,
  promovido_por         uuid REFERENCES auth.users(id),
  descartado_at         timestamptz,
  descartado_razon      text,
  created_by            uuid REFERENCES auth.users(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  notas                 text
);

CREATE INDEX IF NOT EXISTS idx_scenarios_estado      ON scenarios_viaje(estado);
CREATE INDEX IF NOT EXISTS idx_scenarios_created_at  ON scenarios_viaje(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scenarios_created_by  ON scenarios_viaje(created_by);
CREATE INDEX IF NOT EXISTS idx_scenarios_promo_viaje ON scenarios_viaje(promovido_a_viaje_id);

CREATE TABLE IF NOT EXISTS scenarios_viaje_pedidos (
  scenario_id  uuid NOT NULL REFERENCES scenarios_viaje(id) ON DELETE CASCADE,
  pedido_id    uuid NOT NULL REFERENCES pedidos(id),
  orden        int,
  added_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scenario_id, pedido_id)
);

CREATE INDEX IF NOT EXISTS idx_scen_ped_pedido ON scenarios_viaje_pedidos(pedido_id);

-- ───── RLS ─────
ALTER TABLE scenarios_viaje ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenarios_viaje_pedidos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS scen_staff_all ON scenarios_viaje;
CREATE POLICY scen_staff_all ON scenarios_viaje
  FOR ALL USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

DROP POLICY IF EXISTS scen_ped_staff_all ON scenarios_viaje_pedidos;
CREATE POLICY scen_ped_staff_all ON scenarios_viaje_pedidos
  FOR ALL USING (is_logxie_staff()) WITH CHECK (is_logxie_staff());

-- ═══════════════════════════════════════════════════════════════
-- Helper interno: recalcular agregados del scenario
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION _recalc_scenario(p_scenario_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_peso numeric; v_val numeric; v_count int;
  v_origen text; v_destinos text; v_zonas text[];
BEGIN
  SELECT
    COALESCE(SUM(p.peso_kg), 0),
    COALESCE(SUM(p.valor_mercancia), 0),
    COUNT(*)::int,
    MAX(p.origen),
    STRING_AGG(DISTINCT p.destino, ', ' ORDER BY p.destino),
    ARRAY_AGG(DISTINCT p.zona ORDER BY p.zona) FILTER (WHERE p.zona IS NOT NULL AND p.zona <> '')
  INTO v_peso, v_val, v_count, v_origen, v_destinos, v_zonas
  FROM scenarios_viaje_pedidos svp
  JOIN pedidos p ON p.id = svp.pedido_id
  WHERE svp.scenario_id = p_scenario_id;

  UPDATE scenarios_viaje SET
    peso_kg_total         = COALESCE(v_peso, 0),
    valor_mercancia_total = COALESCE(v_val, 0),
    cantidad_pedidos      = COALESCE(v_count, 0),
    origen_sugerido       = v_origen,
    destinos_sugeridos    = v_destinos,
    zonas                 = v_zonas,
    updated_at            = now()
  WHERE id = p_scenario_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_crear(pedido_ids[], nombre?, notas?)
-- Devuelve el scenario_id nuevo.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_crear(
  p_pedido_ids uuid[],
  p_nombre     text DEFAULT NULL,
  p_notas      text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_scenario_id uuid;
  v_nombre text;
  v_origen text; v_zonas_txt text; v_count int;
  v_caller uuid := auth.uid();
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo Logxie staff puede crear scenarios';
  END IF;

  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Scenario requiere al menos 1 pedido';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pedidos WHERE id = ANY(p_pedido_ids) AND estado != 'sin_consolidar'
  ) THEN
    RAISE EXCEPTION 'Solo pedidos en estado sin_consolidar pueden formar un scenario';
  END IF;

  IF p_nombre IS NULL OR trim(p_nombre) = '' THEN
    SELECT COUNT(*)::int, MAX(origen),
           STRING_AGG(DISTINCT zona, '+' ORDER BY zona)
      INTO v_count, v_origen, v_zonas_txt
      FROM pedidos WHERE id = ANY(p_pedido_ids);
    v_nombre := COALESCE(v_origen, '?') ||
                CASE WHEN v_zonas_txt IS NOT NULL THEN ' → ' || v_zonas_txt ELSE '' END ||
                ' (' || v_count || ') ' || to_char(now() AT TIME ZONE 'America/Bogota', 'DD-MM HH24:MI');
  ELSE
    v_nombre := p_nombre;
  END IF;

  INSERT INTO scenarios_viaje (nombre, notas, created_by)
    VALUES (v_nombre, p_notas, v_caller)
    RETURNING id INTO v_scenario_id;

  INSERT INTO scenarios_viaje_pedidos (scenario_id, pedido_id, orden)
    SELECT v_scenario_id, p_id, ord::int
    FROM unnest(p_pedido_ids) WITH ORDINALITY AS t(p_id, ord);

  PERFORM _recalc_scenario(v_scenario_id);

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (v_caller, 'scenario_crear', 'scenario', v_scenario_id,
            jsonb_build_object('nombre', v_nombre,
                               'pedidos_count', array_length(p_pedido_ids, 1)));

  RETURN v_scenario_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_agregar_pedido(scenario_id, pedido_id)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_agregar_pedido(
  p_scenario_id uuid,
  p_pedido_id   uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE v_estado_ped text; v_estado_sc text;
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo staff';
  END IF;

  SELECT estado INTO v_estado_ped FROM pedidos WHERE id = p_pedido_id;
  IF v_estado_ped IS NULL THEN
    RAISE EXCEPTION 'Pedido no existe';
  END IF;
  IF v_estado_ped != 'sin_consolidar' THEN
    RAISE EXCEPTION 'Pedido no está sin_consolidar (estado=%)', v_estado_ped;
  END IF;

  SELECT estado INTO v_estado_sc FROM scenarios_viaje WHERE id = p_scenario_id;
  IF v_estado_sc NOT IN ('borrador','conflictivo') THEN
    RAISE EXCEPTION 'Scenario no editable (estado=%)', v_estado_sc;
  END IF;

  INSERT INTO scenarios_viaje_pedidos (scenario_id, pedido_id)
    VALUES (p_scenario_id, p_pedido_id)
    ON CONFLICT DO NOTHING;

  PERFORM _recalc_scenario(p_scenario_id);

  -- Si estaba 'conflictivo' y ahora ningún pedido es consumido → volver a 'borrador'
  IF v_estado_sc = 'conflictivo' THEN
    IF NOT EXISTS (
      SELECT 1 FROM scenarios_viaje_pedidos svp
      JOIN pedidos p ON p.id = svp.pedido_id
      WHERE svp.scenario_id = p_scenario_id AND p.estado != 'sin_consolidar'
    ) THEN
      UPDATE scenarios_viaje SET estado = 'borrador', updated_at = now()
        WHERE id = p_scenario_id;
    END IF;
  END IF;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'scenario_agregar_pedido', 'scenario', p_scenario_id,
            jsonb_build_object('pedido_id', p_pedido_id));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_quitar_pedido(scenario_id, pedido_id)
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_quitar_pedido(
  p_scenario_id uuid,
  p_pedido_id   uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo staff';
  END IF;

  DELETE FROM scenarios_viaje_pedidos
    WHERE scenario_id = p_scenario_id AND pedido_id = p_pedido_id;

  PERFORM _recalc_scenario(p_scenario_id);

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'scenario_quitar_pedido', 'scenario', p_scenario_id,
            jsonb_build_object('pedido_id', p_pedido_id));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_descartar(scenario_id, razon?)
-- Marca un scenario borrador/conflictivo/invalidado como 'descartado'.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_descartar(
  p_scenario_id uuid,
  p_razon       text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo staff';
  END IF;

  UPDATE scenarios_viaje SET
    estado           = 'descartado',
    descartado_at    = now(),
    descartado_razon = p_razon,
    updated_at       = now()
  WHERE id = p_scenario_id
    AND estado IN ('borrador','conflictivo','invalidado');

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'scenario_descartar', 'scenario', p_scenario_id,
            jsonb_build_object('razon', p_razon));
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_limpiar_consumidos(scenario_id)
-- Quita de un scenario los pedidos que ya se consumieron (estado != sin_consolidar).
-- Si quedan pedidos libres → scenario vuelve a 'borrador'.
-- Si no queda ninguno → 'invalidado'.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_limpiar_consumidos(p_scenario_id uuid)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE v_quitados int;
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo staff';
  END IF;

  WITH d AS (
    DELETE FROM scenarios_viaje_pedidos svp
    USING pedidos p
    WHERE svp.scenario_id = p_scenario_id
      AND p.id = svp.pedido_id
      AND p.estado != 'sin_consolidar'
    RETURNING svp.pedido_id
  )
  SELECT COUNT(*)::int INTO v_quitados FROM d;

  PERFORM _recalc_scenario(p_scenario_id);

  IF EXISTS (SELECT 1 FROM scenarios_viaje_pedidos WHERE scenario_id = p_scenario_id) THEN
    UPDATE scenarios_viaje SET estado = 'borrador', updated_at = now()
      WHERE id = p_scenario_id AND estado = 'conflictivo';
  ELSE
    UPDATE scenarios_viaje SET estado = 'invalidado', updated_at = now()
      WHERE id = p_scenario_id;
  END IF;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'scenario_limpiar', 'scenario', p_scenario_id,
            jsonb_build_object('pedidos_quitados', v_quitados));

  RETURN v_quitados;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- fn_scenario_promover(scenario_id, metadata?)
-- Convierte un scenario borrador en viaje real vía fn_consolidar_pedidos.
-- Marca otros scenarios que compartían pedidos como 'conflictivo'
-- (o 'invalidado' si no les quedó ningún pedido libre).
-- Devuelve viaje_consolidado.id.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fn_scenario_promover(
  p_scenario_id uuid,
  p_metadata    jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_pedido_ids uuid[];
  v_viaje_id uuid;
  v_estado text;
BEGIN
  IF NOT (is_logxie_staff() OR current_setting('role', true) = 'service_role'
          OR session_user IN ('postgres','supabase_admin')) THEN
    RAISE EXCEPTION 'Solo staff';
  END IF;

  SELECT estado INTO v_estado FROM scenarios_viaje WHERE id = p_scenario_id;
  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'Scenario no existe';
  END IF;
  IF v_estado != 'borrador' THEN
    RAISE EXCEPTION 'Solo scenarios en borrador se pueden promover (estado=%)', v_estado;
  END IF;

  SELECT ARRAY_AGG(pedido_id ORDER BY orden NULLS LAST, added_at)
    INTO v_pedido_ids
    FROM scenarios_viaje_pedidos
    WHERE scenario_id = p_scenario_id;

  IF v_pedido_ids IS NULL OR array_length(v_pedido_ids, 1) = 0 THEN
    RAISE EXCEPTION 'Scenario sin pedidos, no se puede promover';
  END IF;

  -- Delega a fn_consolidar_pedidos (valida estados, crea viaje, update pedidos)
  v_viaje_id := fn_consolidar_pedidos(v_pedido_ids, p_metadata);

  UPDATE scenarios_viaje SET
    estado               = 'promovido',
    promovido_a_viaje_id = v_viaje_id,
    promovido_at         = now(),
    promovido_por        = auth.uid(),
    updated_at           = now()
  WHERE id = p_scenario_id;

  -- Otros scenarios borrador que compartían pedidos → conflictivo
  UPDATE scenarios_viaje s SET
    estado = 'conflictivo', updated_at = now()
  WHERE s.id != p_scenario_id
    AND s.estado = 'borrador'
    AND EXISTS (
      SELECT 1 FROM scenarios_viaje_pedidos svp
      WHERE svp.scenario_id = s.id
        AND svp.pedido_id = ANY(v_pedido_ids)
    );

  -- Los conflictivos sin ningún pedido libre → invalidado
  UPDATE scenarios_viaje s SET
    estado = 'invalidado', updated_at = now()
  WHERE s.estado = 'conflictivo'
    AND NOT EXISTS (
      SELECT 1 FROM scenarios_viaje_pedidos svp
      JOIN pedidos p ON p.id = svp.pedido_id
      WHERE svp.scenario_id = s.id AND p.estado = 'sin_consolidar'
    );

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
    VALUES (auth.uid(), 'scenario_promover', 'scenario', p_scenario_id,
            jsonb_build_object('viaje_id', v_viaje_id,
                               'pedidos_count', array_length(v_pedido_ids, 1)));

  RETURN v_viaje_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- Extender CHECK de acciones_operador.accion para los tipos nuevos.
-- Intenta DROP+ADD; si falla por data existente, sale con warning
-- y la tabla queda sin constraint (data preservada).
-- ═══════════════════════════════════════════════════════════════
DO $$
BEGIN
  BEGIN
    ALTER TABLE acciones_operador DROP CONSTRAINT IF EXISTS acciones_operador_accion_check;
    ALTER TABLE acciones_operador ADD CONSTRAINT acciones_operador_accion_check
      CHECK (accion IN (
        'consolidar','desconsolidar','ajustar_precio','adjudicar','cancelar',
        'publicar','invitar','asignar_directo','reabrir','cerrar','reabrir_finalizado',
        'agregar_pedido','quitar_pedido','marcar_revisado','marcar_no_revisado',
        'pedido_cancelar','pedido_resetear','pedido_clonar','pedido_editar',
        'pedido_cambiar_estado','pedido_eliminar','pedido_marcar_novedad',
        'sync','cleanup_ghost','reabrir_cancelado',
        'scenario_crear','scenario_agregar_pedido','scenario_quitar_pedido',
        'scenario_descartar','scenario_promover','scenario_limpiar'
      ));
  EXCEPTION WHEN check_violation THEN
    RAISE WARNING 'No se pudo recrear check constraint de acciones_operador — hay valores no listados. Queda sin constraint.';
  END;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- Smoke test al final: verifica que las funciones existen
-- ═══════════════════════════════════════════════════════════════
DO $$
BEGIN
  PERFORM 1 FROM pg_proc WHERE proname = 'fn_scenario_crear';
  IF NOT FOUND THEN RAISE EXCEPTION 'fn_scenario_crear no existe tras la migración'; END IF;
  PERFORM 1 FROM pg_proc WHERE proname = 'fn_scenario_promover';
  IF NOT FOUND THEN RAISE EXCEPTION 'fn_scenario_promover no existe'; END IF;
  RAISE NOTICE 'scenarios_viaje.sql aplicado OK';
END $$;
