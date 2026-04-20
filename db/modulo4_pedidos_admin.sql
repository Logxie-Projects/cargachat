-- ============================================================
-- Admin de pedidos: editar + cambiar estado libre + eliminar
-- ============================================================

BEGIN;

-- Extender CHECK acciones.accion
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.acciones_operador'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%accion%'
  LOOP
    EXECUTE format('ALTER TABLE acciones_operador DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE acciones_operador
  ADD CONSTRAINT acciones_operador_accion_check
  CHECK (accion IN (
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar',
    'ajustar_precio','publicar','invitar','asignar_directo',
    'adjudicar','cancelar','reasignar','reabrir',
    'sync_viajes','sync_pedidos',
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch','clonar_pedido',
    'editar_pedido','cambiar_estado_pedido','eliminar_pedido'
  ));

-- ============================================================
-- fn_pedido_editar
--   Update parcial de campos. Solo acepta whitelist de campos editables.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedido_editar(
  p_pedido_id uuid,
  p_campos    jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_antes jsonb;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede editar pedidos';
  END IF;

  SELECT to_jsonb(p) INTO v_antes FROM pedidos p WHERE id = p_pedido_id;
  IF v_antes IS NULL THEN RAISE EXCEPTION 'pedido % no existe', p_pedido_id; END IF;

  UPDATE pedidos SET
    pedido_ref       = COALESCE(p_campos->>'pedido_ref', pedido_ref),
    empresa          = COALESCE(_norm_empresa(p_campos->>'empresa'), empresa),
    zona             = COALESCE(p_campos->>'zona', zona),
    origen           = COALESCE(p_campos->>'origen', origen),
    destino          = COALESCE(p_campos->>'destino', destino),
    fecha_cargue     = COALESCE((p_campos->>'fecha_cargue')::timestamptz, fecha_cargue),
    fecha_entrega    = COALESCE((p_campos->>'fecha_entrega')::timestamptz, fecha_entrega),
    peso_kg          = COALESCE((p_campos->>'peso_kg')::numeric, peso_kg),
    tipo_mercancia   = COALESCE(p_campos->>'tipo_mercancia', tipo_mercancia),
    contenedores     = COALESCE((p_campos->>'contenedores')::int, contenedores),
    cajas            = COALESCE((p_campos->>'cajas')::int, cajas),
    bidones          = COALESCE((p_campos->>'bidones')::int, bidones),
    canecas          = COALESCE((p_campos->>'canecas')::int, canecas),
    unidades_sueltas = COALESCE((p_campos->>'unidades_sueltas')::int, unidades_sueltas),
    valor_mercancia  = COALESCE((p_campos->>'valor_mercancia')::numeric, valor_mercancia),
    valor_factura    = COALESCE((p_campos->>'valor_factura')::numeric, valor_factura),
    cliente_nombre   = COALESCE(p_campos->>'cliente_nombre', cliente_nombre),
    contacto_nombre  = COALESCE(p_campos->>'contacto_nombre', contacto_nombre),
    contacto_tel     = COALESCE(p_campos->>'contacto_tel', contacto_tel),
    direccion        = COALESCE(p_campos->>'direccion', direccion),
    horario          = COALESCE(p_campos->>'horario', horario),
    llamar_antes     = COALESCE((p_campos->>'llamar_antes')::boolean, llamar_antes),
    observaciones    = COALESCE(p_campos->>'observaciones', observaciones),
    motivo_viaje     = COALESCE(p_campos->>'motivo_viaje', motivo_viaje),
    prioridad        = COALESCE(p_campos->>'prioridad', prioridad),
    vendedor         = COALESCE(p_campos->>'vendedor', vendedor),
    jefe_zona        = COALESCE(p_campos->>'jefe_zona', jefe_zona),
    coordinador      = COALESCE(p_campos->>'coordinador', coordinador),
    proveedor        = COALESCE(p_campos->>'proveedor', proveedor)
  WHERE id = p_pedido_id;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'editar_pedido', 'pedido', p_pedido_id,
    jsonb_build_object('antes', v_antes, 'campos_recibidos', p_campos));
END;
$$;

-- ============================================================
-- fn_pedidos_cambiar_estado_batch
--   Salta validaciones del state machine. Staff admin puede forzar
--   cualquier transición con razón. Útil para corregir inconsistencias
--   (ej: pedido con estado=consolidado pero viaje_id=NULL).
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedidos_cambiar_estado_batch(
  p_pedido_ids  uuid[],
  p_nuevo_estado text,
  p_razon       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cambiados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede cambiar estado de pedidos';
  END IF;

  IF p_nuevo_estado NOT IN ('sin_consolidar','consolidado','asignado','en_ruta','entregado','entregado_novedad','rechazado','cancelado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_nuevo_estado;
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida';
  END IF;

  UPDATE pedidos SET estado = p_nuevo_estado
  WHERE id = ANY(p_pedido_ids);
  GET DIAGNOSTICS v_cambiados = ROW_COUNT;

  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'cambiar_estado_pedido', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'pedido_ids', to_jsonb(p_pedido_ids),
      'nuevo_estado', p_nuevo_estado,
      'cambiados', v_cambiados,
      'razon', p_razon
    ));

  RETURN jsonb_build_object('cambiados', v_cambiados);
END;
$$;

-- ============================================================
-- fn_pedidos_eliminar_batch
--   DELETE hard. Captura snapshot completo de cada pedido en audit
--   metadata ANTES de borrar — único recurso de recuperación.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_pedidos_eliminar_batch(
  p_pedido_ids uuid[],
  p_razon      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snapshot jsonb;
  v_eliminados int;
BEGIN
  IF NOT is_logxie_staff()
     AND NOT (current_setting('role', true) = 'service_role')
     AND session_user NOT IN ('postgres','supabase_admin') THEN
    RAISE EXCEPTION 'Solo logxie_staff puede eliminar pedidos';
  END IF;

  IF p_razon IS NULL OR trim(p_razon) = '' THEN
    RAISE EXCEPTION 'Razón requerida para eliminar pedidos';
  END IF;
  IF p_pedido_ids IS NULL OR array_length(p_pedido_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Lista de pedidos vacía';
  END IF;

  -- Snapshot antes de borrar
  SELECT jsonb_agg(to_jsonb(p)) INTO v_snapshot
  FROM pedidos p WHERE id = ANY(p_pedido_ids);

  -- Audit PRIMERO (por si falla el delete, queda trazabilidad del intento)
  INSERT INTO acciones_operador (user_id, accion, entidad_tipo, entidad_id, metadata)
  VALUES (auth.uid(), 'eliminar_pedido', 'pedido', '00000000-0000-0000-0000-000000000000'::uuid,
    jsonb_build_object(
      'pedido_ids', to_jsonb(p_pedido_ids),
      'razon', p_razon,
      'snapshot', v_snapshot
    ));

  DELETE FROM pedidos WHERE id = ANY(p_pedido_ids);
  GET DIAGNOSTICS v_eliminados = ROW_COUNT;

  RETURN jsonb_build_object('eliminados', v_eliminados, 'snapshot_guardado', true);
END;
$$;

COMMIT;
