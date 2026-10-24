
USE PlazaVea_G6_1000Productos_50Tiendas;
GO

-- EVIDENCIA E-02: Dataset procesado del Data Mart

-- Verificar las dimensiones y la tabla de hechos
SELECT 'DimProducto' AS tabla, COUNT(*) AS total_registros
FROM bi.DimProducto

UNION ALL

SELECT 'DimTienda', COUNT(*)
FROM bi.DimTienda

UNION ALL

SELECT 'FactDetalleVenta', COUNT(*)
FROM bi.FactDetalleVenta;
GO

--  Consultar los ingresos y unidades por tienda y categoría
SELECT
    t.nombre AS tienda,
    p.categoria,
    SUM(f.cantidad) AS unidades_vendidas,
    SUM(f.importe) AS ingresos_totales
FROM bi.FactDetalleVenta AS f
INNER JOIN bi.DimTienda AS t
    ON f.tienda_key = t.tienda_key
INNER JOIN bi.DimProducto AS p
    ON f.producto_key = p.producto_key
GROUP BY
    t.nombre,
    p.categoria
ORDER BY ingresos_totales DESC;
GO
