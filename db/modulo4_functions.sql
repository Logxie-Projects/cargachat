-- ============================================================
-- MÓDULO 4 — Postgres functions (paso 3 de 3)
--
-- 9 funciones que soportan el ciclo completo de control:
--   Consolidación: consolidar, agregar_pedido, quitar_pedido, desconsolidar
--   Precio:        ajustar_precio
--   Subasta:       publicar, invitar, asignar_directo, adjudicar_oferta
--
-- Todas son SECURITY DEFINER y chequean is_logxie_staff() al inicio.
-- Todas escriben audit a acciones_operador.
-- Todas son transaccionales (se revierten completas si falla algo).
--
-- Precondición: perfiles.sql + modulo4_schema.sql + modulo4_schema_extra.sql
-- Idempotente (CREATE OR REPLACE).
-- ============================================================

BEGIN;

-- ============================================================
-- Helper interno: recalcular agregados de un viaje desde sus pedidos
-- ============================================================
CREATE OR REPLACE FUNCTION _recalc_viaje_agregados(p_viaje_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_agg record;
BEGIN
  SELECT
    COUNT(*)                                           AS cantidad,
    string_agg(DISTINCT empresa, ', ' ORDER BY empresa) AS empresa,
    string_agg(DISTINCT zona,    ', ' ORDER BY zona)    AS zona,
    COALESCE(SUM(peso_kg), 0)                          AS peso_kg,
    COALESCE(SUM(valor_mercancia), 0)                  AS valor_mercancia,
    COALESCE(SUM(contenedores), 0)                     AS contenedores,
    COALESCE(SUM(cajas), 0)                            AS cajas,
    COALESCE(SUM(bidones), 0)                          AS bidones,
    COALESCE(SUM(canecas), 0)                          AS canecas,
    COALESCE(SUM(unidades_sueltas), 0)                 AS unidades_sueltas,
    string_agg(pedido_ref, ', ' ORDER BY pedido_ref)
      FILTER (WHERE pedido_ref IS NOT NULL)            AS consecutivos
  INTO v_agg
  FROM pedidos WHERE viaje_id = p_viaje_id;

  UPDATE viajes_consolidados v
  SET
    cantidad_pedidos = v_agg.cantidad,
    empresa          = v_agg.empresa,
    zona             = v_agg.zona,
    peso_kg          = v_agg.peso_kg,
    valor_mercancia  = v_agg.valor_mercancia,
    contenedores     = v_agg.contenedores,
    cajas            = v_agg.cajas,
    bidones          = v_agg.bidones,
    canecas          = v_agg.canecas,
    unidades_sueltas = v_agg.unidades_sueltas,
    consecutivos     = v_agg.consecutivos
  WHERE v.id = p_viaje_id;
END;
$$;

-- ============================================================
-- 1. fn_consolidar_pedidos
--    Crea un viaje nuevo con N pedidos.
--    Todos los pedidos deben estar en sin_consolidar.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_consolidar_pedidos(
  p_pedido_ids uuid[],
  p_metadata   jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id          uuid := auth.uid();
  v_viaje_id         uuid;
  v_viaje_ref        text;
  v_cliente_id       uuid;
  v_distinct_clientes int;
  v_count            int;
  v_fecha_cargue     timestamptz;
  v_origen           text;
  v_destino          text;
  v_flete_total      numeric;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede consolidar pedidos';
  END IF;

  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'pedido_ids vacío';
  END IF;

  -- Validar que todos existen y están sin_consolidar
  SELECT COUNT(*), COUNT(DISTINCT cliente_id)
  INTO v_count, v_distinct_clientes
  FROM pedidos
  WHERE id = ANY(p_pedido_ids) AND estado = 'sin_consolidar';

  IF v_count <> array_length(p_pedido_ids, 1) THEN
    RAISE EXCEPTION 'Algunos pedidos no existen o no están en sin_consolidar (encontrados: %, esperados: %)',
      v_count, array_length(p_pedido_ids, 1);
  END IF;

  -- cliente_id: solo si todos son del mismo cliente
  IF v_distinct_clientes = 1 THEN
    SELECT cliente_id INTO v_cliente_id FROM pedidos WHERE id = p_pedido_ids[1];
  END IF;

  -- Defaults desde pedidos (pueden ser overridden via metadata)
  SELECT MIN(fecha_cargue) INTO v_fecha_cargue FROM pedidos WHERE id = ANY(p_pedido_ids);
  v_fecha_cargue := COALESCE((p_metadata->>'fecha_cargue')::timestamptz, v_fecha_cargue);

  SELECT string_agg(DISTINCT origen, ', ' ORDER BY origen) INTO v_origen
    FROM pedidos WHERE id = ANY(p_pedido_ids);
  v_origen := COALESCE(p_metadata->>'origen', v_origen);

  SELECT string_agg(DISTINCT destino, ', ' ORDER BY destino) INTO v_destino
    FROM pedidos WHERE id = ANY(p_pedido_ids);
  v_destino := COALESCE(p_metadata->>'destino', v_destino);

  v_flete_total := COALESCE((p_metadata->>'flete_total')::numeric, 0);

  -- Generar viaje_ref único: NF-YYMMDDHHMISS-XXXX
  v_viaje_ref := 'NF-' || to_char(now(), 'YYMMDD-HH24MISS') ||
                 '-' || substr(gen_random_uuid()::text, 1, 4);

  -- Insertar viaje (agregados quedarán en 0, se recalculan abajo)
  INSERT INTO viajes_consolidados (
    viaje_ref, cliente_id, fecha_consolidacion, fecha_cargue,
    origen, destino, flete_total,
    fuente, estado, observaciones,
    mes, anio, subasta_tipo,
    raw_payload
  ) VALUES (
    v_viaje_ref, v_cliente_id, now(), v_fecha_cargue,
    v_origen, v_destino, v_flete_total,
    'netfleet', 'pendiente', p_metadata->>'observaciones',
    EXTRACT(MONTH FROM COALESCE(v_fecha_cargue, now()))::int,
    EXTRACT(YEAR  FROM COALESCE(v_fecha_cargue, now()))::int,
    'abierta',
    jsonb_build_object(
      'via', 'fn_consolidar_pedidos',
      'pedido_ids', to_jsonb(p_pedido_ids),
      'metadata_input', p_metadata
    )::text
  ) RETURNING id INTO v_viaje_id;

  -- Link pedidos → viaje y cambiar estado
  UPDATE pedidos
  SET viaje_id = v_viaje_id, estado = 'consolidado'
  WHERE id = ANY(p_pedido_ids);

  -- Recalcular agregados (peso, valor, cantidad, consecutivos, etc.)
  PERFORM _recalc_viaje_agregados(v_viaje_id);

  -- Audit
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (v_user_id, 'consolidar', 'viaje', v_viaje_id,
    jsonb_build_object(
      'pedido_ids', to_jsonb(p_pedido_ids),
      'cantidad',   v_count,
      'cliente_id', v_cliente_id,
      'flete_total', v_flete_total
    ));

  RETURN v_viaje_id;
END;
$$;

-- ============================================================
-- 2. fn_agregar_pedido_a_viaje
--    Añade 1 pedido a un viaje existente. Solo si viaje=pendiente.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_agregar_pedido_a_viaje(
  p_viaje_id  uuid,
  p_pedido_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado  text;
  v_pedido_estado text;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede modificar viajes';
  END IF;

  SELECT estado INTO v_viaje_estado FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'No se puede agregar pedido: viaje está en estado %', v_viaje_estado;
  END IF;

  SELECT estado INTO v_pedido_estado FROM pedidos WHERE id = p_pedido_id;
  IF v_pedido_estado IS NULL THEN
    RAISE EXCEPTION 'pedido % no existe', p_pedido_id;
  END IF;
  IF v_pedido_estado <> 'sin_consolidar' THEN
    RAISE EXCEPTION 'Pedido no está sin_consolidar (estado actual: %)', v_pedido_estado;
  END IF;

  UPDATE pedidos SET viaje_id = p_viaje_id, estado = 'consolidado' WHERE id = p_pedido_id;
  PERFORM _recalc_viaje_agregados(p_viaje_id);

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'agregar_pedido', 'viaje', p_viaje_id,
    jsonb_build_object('pedido_id', p_pedido_id));
END;
$$;

-- ============================================================
-- 3. fn_quitar_pedido_de_viaje
--    Saca 1 pedido de su viaje. Si era el último, cancela el viaje.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_quitar_pedido_de_viaje(p_pedido_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_id     uuid;
  v_viaje_estado text;
  v_restantes    int;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede modificar viajes';
  END IF;

  SELECT viaje_id INTO v_viaje_id FROM pedidos WHERE id = p_pedido_id;
  IF v_viaje_id IS NULL THEN
    RAISE EXCEPTION 'Pedido no está en ningún viaje (o no existe)';
  END IF;

  SELECT estado INTO v_viaje_estado FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'No se puede quitar: viaje está en estado %', v_viaje_estado;
  END IF;

  -- Liberar pedido
  UPDATE pedidos SET viaje_id = NULL, estado = 'sin_consolidar' WHERE id = p_pedido_id;

  -- ¿Quedan pedidos en el viaje?
  SELECT COUNT(*) INTO v_restantes FROM pedidos WHERE viaje_id = v_viaje_id;

  IF v_restantes = 0 THEN
    UPDATE viajes_consolidados SET estado = 'cancelado' WHERE id = v_viaje_id;
  ELSE
    PERFORM _recalc_viaje_agregados(v_viaje_id);
  END IF;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'quitar_pedido', 'viaje', v_viaje_id,
    jsonb_build_object(
      'pedido_id', p_pedido_id,
      'pedidos_restantes', v_restantes,
      'auto_cancelado', v_restantes = 0
    ));
END;
$$;

-- ============================================================
-- 4. fn_desconsolidar_viaje
--    Cancela viaje + libera todos sus pedidos.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_desconsolidar_viaje(p_viaje_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado text;
  v_liberados    int;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede desconsolidar';
  END IF;

  SELECT estado INTO v_viaje_estado FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se desconsolidan viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;

  UPDATE pedidos SET viaje_id = NULL, estado = 'sin_consolidar' WHERE viaje_id = p_viaje_id;
  GET DIAGNOSTICS v_liberados = ROW_COUNT;

  UPDATE viajes_consolidados SET estado = 'cancelado' WHERE id = p_viaje_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'desconsolidar', 'viaje', p_viaje_id,
    jsonb_build_object('pedidos_liberados', v_liberados));

  RETURN v_liberados;
END;
$$;

-- ============================================================
-- 5. fn_ajustar_precio_viaje
--    Cambia flete_total. Solo antes de adjudicar.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_ajustar_precio_viaje(
  p_viaje_id    uuid,
  p_nuevo_flete numeric,
  p_razon       text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado text;
  v_precio_anterior numeric;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede ajustar precios';
  END IF;

  IF p_nuevo_flete IS NULL OR p_nuevo_flete <= 0 THEN
    RAISE EXCEPTION 'nuevo_flete debe ser > 0';
  END IF;
  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida al ajustar precio';
  END IF;

  SELECT estado, flete_total INTO v_viaje_estado, v_precio_anterior
    FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se ajusta precio en viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;

  UPDATE viajes_consolidados SET flete_total = p_nuevo_flete WHERE id = p_viaje_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'ajustar_precio', 'viaje', p_viaje_id,
    jsonb_build_object(
      'precio_anterior', v_precio_anterior,
      'precio_nuevo',    p_nuevo_flete,
      'razon',           p_razon
    ));
END;
$$;

-- ============================================================
-- 6. fn_publicar_viaje
--    Marca viaje como publicado (abre subasta).
--    tipo: 'abierta' (todos ven) | 'cerrada' (solo invitados ven)
-- ============================================================
CREATE OR REPLACE FUNCTION fn_publicar_viaje(
  p_viaje_id uuid,
  p_tipo     text DEFAULT 'abierta'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado text;
  v_publicado_at timestamptz;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede publicar viajes';
  END IF;

  IF p_tipo NOT IN ('abierta', 'cerrada') THEN
    RAISE EXCEPTION 'tipo debe ser abierta o cerrada (recibido: %)', p_tipo;
  END IF;

  SELECT estado, publicado_at INTO v_viaje_estado, v_publicado_at
    FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se publican viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;
  IF v_publicado_at IS NOT NULL THEN
    RAISE EXCEPTION 'Viaje ya publicado el %', v_publicado_at;
  END IF;

  UPDATE viajes_consolidados
  SET publicado_at = now(), subasta_tipo = p_tipo
  WHERE id = p_viaje_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'publicar', 'viaje', p_viaje_id,
    jsonb_build_object('subasta_tipo', p_tipo));
END;
$$;

-- ============================================================
-- 7. fn_invitar_transportadora
--    Invita 1 transportadora a la subasta (solo si cerrada).
--    Si viaje es subasta 'abierta', no hace falta invitar.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_invitar_transportadora(
  p_viaje_id          uuid,
  p_transportadora_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado text;
  v_subasta_tipo text;
  v_publicado_at timestamptz;
  v_invitacion_id uuid;
  v_transportadora_activa boolean;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede invitar transportadoras';
  END IF;

  SELECT estado, subasta_tipo, publicado_at
    INTO v_viaje_estado, v_subasta_tipo, v_publicado_at
    FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se invita en viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;

  SELECT activo INTO v_transportadora_activa
    FROM transportadoras WHERE id = p_transportadora_id;
  IF v_transportadora_activa IS NULL THEN
    RAISE EXCEPTION 'transportadora % no existe', p_transportadora_id;
  END IF;
  IF v_transportadora_activa = false THEN
    RAISE EXCEPTION 'transportadora está inactiva';
  END IF;

  -- Insert idempotente (si ya estaba invitada, no duplica)
  INSERT INTO invitaciones_subasta (viaje_id, transportadora_id, invitado_por)
  VALUES (p_viaje_id, p_transportadora_id, auth.uid())
  ON CONFLICT (viaje_id, transportadora_id) DO NOTHING
  RETURNING id INTO v_invitacion_id;

  IF v_invitacion_id IS NULL THEN
    -- Ya existía — recuperarla
    SELECT id INTO v_invitacion_id FROM invitaciones_subasta
      WHERE viaje_id = p_viaje_id AND transportadora_id = p_transportadora_id;
  END IF;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'invitar', 'viaje', p_viaje_id,
    jsonb_build_object(
      'transportadora_id', p_transportadora_id,
      'invitacion_id', v_invitacion_id
    ));

  RETURN v_invitacion_id;
END;
$$;

-- ============================================================
-- 8. fn_asignar_transportadora_directo
--    Skipea subasta: asigna directo a un proveedor al precio acordado.
--    Viaje pasa a 'confirmado' sin pasar por ofertas.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_asignar_transportadora_directo(
  p_viaje_id          uuid,
  p_transportadora_id uuid,
  p_precio            numeric,
  p_razon             text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_estado text;
  v_transp_nombre text;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede asignar directo';
  END IF;

  IF p_precio IS NULL OR p_precio <= 0 THEN
    RAISE EXCEPTION 'precio debe ser > 0';
  END IF;
  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para asignación directa';
  END IF;

  SELECT estado INTO v_viaje_estado FROM viajes_consolidados WHERE id = p_viaje_id;
  IF v_viaje_estado IS NULL THEN
    RAISE EXCEPTION 'viaje % no existe', p_viaje_id;
  END IF;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se asigna directo en viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;

  SELECT nombre INTO v_transp_nombre FROM transportadoras
    WHERE id = p_transportadora_id AND activo = true;
  IF v_transp_nombre IS NULL THEN
    RAISE EXCEPTION 'transportadora no existe o está inactiva';
  END IF;

  UPDATE viajes_consolidados
  SET
    transportadora_id  = p_transportadora_id,
    proveedor          = v_transp_nombre,  -- mantiene campo legacy
    flete_total        = p_precio,
    estado             = 'confirmado',
    adjudicado_at      = now(),
    adjudicacion_tipo  = 'directa',
    publicado_at       = COALESCE(publicado_at, now())
  WHERE id = p_viaje_id;

  -- Pedidos del viaje → asignados
  UPDATE pedidos SET estado = 'asignado' WHERE viaje_id = p_viaje_id AND estado = 'consolidado';

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'asignar_directo', 'viaje', p_viaje_id,
    jsonb_build_object(
      'transportadora_id', p_transportadora_id,
      'transportadora_nombre', v_transp_nombre,
      'precio', p_precio,
      'razon', p_razon
    ));
END;
$$;

-- ============================================================
-- 9. fn_adjudicar_oferta
--    Acepta oferta ganadora. Rechaza las demás del viaje.
--    Viaje → 'confirmado' con el precio y proveedor de la oferta.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_adjudicar_oferta(p_oferta_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viaje_id          uuid;
  v_transportadora_id uuid;
  v_precio            numeric;
  v_oferta_estado     text;
  v_viaje_estado      text;
  v_transp_nombre     text;
  v_rechazadas        int;
BEGIN
  IF NOT is_logxie_staff() THEN
    RAISE EXCEPTION 'Solo logxie_staff puede adjudicar ofertas';
  END IF;

  SELECT viaje_id, transportadora_id, precio_oferta, estado
    INTO v_viaje_id, v_transportadora_id, v_precio, v_oferta_estado
    FROM ofertas WHERE id = p_oferta_id;
  IF v_viaje_id IS NULL THEN
    RAISE EXCEPTION 'oferta % no existe', p_oferta_id;
  END IF;
  IF v_oferta_estado <> 'activa' THEN
    RAISE EXCEPTION 'oferta no está activa (estado: %)', v_oferta_estado;
  END IF;

  SELECT estado INTO v_viaje_estado FROM viajes_consolidados WHERE id = v_viaje_id;
  IF v_viaje_estado <> 'pendiente' THEN
    RAISE EXCEPTION 'Solo se adjudica en viajes pendientes (estado actual: %)', v_viaje_estado;
  END IF;

  -- Aceptar la ganadora
  UPDATE ofertas SET estado = 'aceptada', cerrada_at = now() WHERE id = p_oferta_id;

  -- Rechazar las demás activas del mismo viaje
  UPDATE ofertas
  SET estado = 'rechazada', cerrada_at = now()
  WHERE viaje_id = v_viaje_id AND estado = 'activa' AND id <> p_oferta_id;
  GET DIAGNOSTICS v_rechazadas = ROW_COUNT;

  -- Actualizar viaje
  SELECT nombre INTO v_transp_nombre FROM transportadoras WHERE id = v_transportadora_id;

  UPDATE viajes_consolidados
  SET
    transportadora_id  = v_transportadora_id,
    proveedor          = v_transp_nombre,
    flete_total        = v_precio,
    estado             = 'confirmado',
    adjudicado_at      = now(),
    adjudicacion_tipo  = 'subasta',
    oferta_ganadora_id = p_oferta_id
  WHERE id = v_viaje_id;

  -- Pedidos del viaje → asignados
  UPDATE pedidos SET estado = 'asignado' WHERE viaje_id = v_viaje_id AND estado = 'consolidado';

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'adjudicar', 'oferta', p_oferta_id,
    jsonb_build_object(
      'viaje_id', v_viaje_id,
      'transportadora_id', v_transportadora_id,
      'precio', v_precio,
      'ofertas_rechazadas', v_rechazadas
    ));
END;
$$;

COMMIT;

-- ============================================================
-- Smoke test (corre aparte cuando haya data real):
--
--   SELECT fn_consolidar_pedidos(
--     ARRAY[
--       '3f...'::uuid,   -- 3 pedidos sin_consolidar del mismo cliente
--       '4a...'::uuid,
--       '5b...'::uuid
--     ],
--     '{"observaciones":"test","flete_total":2500000}'::jsonb
--   );
--
--   SELECT fn_publicar_viaje('<viaje_id>'::uuid, 'abierta');
--   SELECT fn_invitar_transportadora('<viaje_id>'::uuid, '<transp_id>'::uuid);
--   SELECT fn_asignar_transportadora_directo('<viaje_id>'::uuid, '<transp_id>'::uuid, 3200000, 'cliente preferente');
--
--   SELECT * FROM acciones_operador ORDER BY created_at DESC LIMIT 20;
-- ============================================================
