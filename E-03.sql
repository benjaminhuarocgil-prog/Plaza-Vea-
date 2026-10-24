
USE PlazaVea_G6_1000Productos_50Tiendas;
GO

-- EVIDENCIA E-03: Validación de datos sintéticos

--  Verificar productos, tiendas y ventas
SELECT
    (SELECT COUNT(*) FROM operacion.Producto)
        AS total_productos,
    (SELECT COUNT(*) FROM operacion.Tienda)
        AS total_tiendas,
    (SELECT COUNT(*) FROM operacion.Venta)
        AS total_ventas;
GO

--  Contar ventas por estado
SELECT
    estado,
    COUNT(*) AS cantidad_ventas
FROM operacion.Venta
GROUP BY estado
ORDER BY estado;
GO

-- Verificar cantidad de ventas por tienda
SELECT
    t.id_tienda,
    t.nombre AS tienda,
    COUNT(v.id_venta) AS cantidad_ventas
FROM operacion.Tienda AS t
LEFT JOIN operacion.Venta AS v
    ON t.id_tienda = v.id_tienda
GROUP BY
    t.id_tienda,
    t.nombre
ORDER BY t.id_tienda;
GO
