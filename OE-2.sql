/* EVIDENCIA OE-02: análisis comercial desde el Data Mart */
SELECT
    t.nombre AS tienda,
    p.categoria,
    SUM(f.cantidad) AS unidades_vendidas,
    SUM(f.importe) AS ingresos
FROM bi.FactDetalleVenta f
JOIN bi.DimTienda t
    ON t.tienda_key = f.tienda_key
JOIN bi.DimProducto p
    ON p.producto_key = f.producto_key
GROUP BY t.nombre, p.categoria
ORDER BY ingresos DESC;
GO