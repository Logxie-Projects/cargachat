SELECT
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
   WHERE conrelid = 'public.acciones_operador'::regclass
     AND conname = 'acciones_operador_accion_check') AS check_def,
  (SELECT COUNT(DISTINCT accion) FROM acciones_operador) AS valores_en_uso;
