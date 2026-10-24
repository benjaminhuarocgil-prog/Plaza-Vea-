SELECT
    s.name AS Esquema,
    t.name AS Tabla
FROM sys.tables t
INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id
ORDER BY s.name, t.name;