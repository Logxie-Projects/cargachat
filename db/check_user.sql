-- Ver el estado actual: qué columnas tiene perfiles y qué usuarios hay
SELECT
  u.id,
  u.email,
  u.created_at AS auth_created,
  u.email_confirmed_at IS NOT NULL AS email_confirmed,
  p.tipo,
  p.estado,
  p.nombre,
  (p.id IS NOT NULL) AS tiene_perfil
FROM auth.users u
LEFT JOIN perfiles p ON p.id = u.id
ORDER BY u.created_at DESC;
