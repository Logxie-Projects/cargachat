-- Patch: extender acciones_operador.accion CHECK con los 6 nuevos valores de scenarios
-- Lista completa = actual + scenario_*
ALTER TABLE acciones_operador DROP CONSTRAINT IF EXISTS acciones_operador_accion_check;
ALTER TABLE acciones_operador ADD CONSTRAINT acciones_operador_accion_check
  CHECK (accion IN (
    -- Originales module 4
    'consolidar','agregar_pedido','quitar_pedido','desconsolidar','ajustar_precio',
    'publicar','invitar','asignar_directo','adjudicar','cancelar','reasignar','reabrir',
    -- Sync
    'sync_viajes','sync_pedidos','sync_seguimiento','run_linkers','cleanup_ghosts',
    -- Pedidos admin
    'revisar_pedido','desmarcar_revision',
    'cerrar','cerrar_batch','reabrir_cierre',
    'cancelar_pedidos_batch','resetear_pedidos_batch',
    'clonar_pedido','editar_pedido','cambiar_estado_pedido','eliminar_pedido',
    'asociar_viaje','desasociar_viaje',
    -- Tracking/entrega
    'reintentar_entrega','marcar_salida_cargue','marcar_llegada_cargue',
    'marcar_llegada_descargue','marcar_salida_descargue',
    'subir_cumplido',
    -- Facturación (futuro)
    'crear_factura','marcar_factura_pagada',
    -- Scenarios (NUEVOS)
    'scenario_crear','scenario_agregar_pedido','scenario_quitar_pedido',
    'scenario_descartar','scenario_promover','scenario_limpiar'
  ));

-- Verificar
DO $$
DECLARE n int;
BEGIN
  SELECT COUNT(*) INTO n FROM pg_constraint c JOIN pg_class t ON c.conrelid=t.oid
    WHERE t.relname='acciones_operador' AND c.conname='acciones_operador_accion_check';
  IF n = 0 THEN RAISE EXCEPTION 'constraint no aplicó'; END IF;
  RAISE NOTICE 'constraint reaplicado con scenario_*';
END $$;
