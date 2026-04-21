-- Policies para buckets (Supabase Storage usa storage.objects table)

-- CUMPLIDOS: lectura pública, escritura por authenticated
DROP POLICY IF EXISTS "cumplidos_public_read" ON storage.objects;
CREATE POLICY "cumplidos_public_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'cumplidos');

DROP POLICY IF EXISTS "cumplidos_auth_insert" ON storage.objects;
CREATE POLICY "cumplidos_auth_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'cumplidos');

DROP POLICY IF EXISTS "cumplidos_staff_delete" ON storage.objects;
CREATE POLICY "cumplidos_staff_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'cumplidos' AND is_logxie_staff());

-- FACTURAS: lectura solo authenticated (Logxie + transportadora dueña vía signed url), escritura authenticated
DROP POLICY IF EXISTS "facturas_auth_read" ON storage.objects;
CREATE POLICY "facturas_auth_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'facturas');

DROP POLICY IF EXISTS "facturas_auth_insert" ON storage.objects;
CREATE POLICY "facturas_auth_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'facturas');

DROP POLICY IF EXISTS "facturas_staff_delete" ON storage.objects;
CREATE POLICY "facturas_staff_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'facturas' AND is_logxie_staff());

SELECT policyname FROM pg_policies WHERE schemaname='storage' AND tablename='objects';
