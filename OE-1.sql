
USE PlazaVea_G6_1000Productos_50Tiendas;
GO

/* EVIDENCIA OE-01: estructura y datos de la base */
SELECT
    (SELECT COUNT(*) FROM sys.tables
     WHERE schema_id IN (SCHEMA_ID('operacion'),
                         SCHEMA_ID('bi'),
                         SCHEMA_ID('control'))) AS total_tablas,
    (SELECT COUNT(*) FROM operacion.Producto) AS total_productos,
    (SELECT COUNT(*) FROM operacion.Tienda) AS total_tiendas,
    (SELECT COUNT(*) FROM operacion.Venta) AS total_ventas;

-- Comprobar productos duplicados
SELECT nombre, COUNT(*) AS repeticiones
FROM operacion.Producto
GROUP BY nombre
HAVING COUNT(*) > 1;
GO

