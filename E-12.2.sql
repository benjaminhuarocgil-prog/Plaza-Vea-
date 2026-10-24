SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS Esquema,
    OBJECT_NAME(parent_object_id) AS Tabla,
    name AS Restriccion,
    type_desc AS Tipo
FROM sys.objects
WHERE type IN ('F', 'C', 'UQ', 'PK')
  AND OBJECT_SCHEMA_NAME(parent_object_id)
      IN ('operacion', 'bi', 'control')
ORDER BY Esquema, Tabla;