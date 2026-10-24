/* EVIDENCIA OE-03: procesamiento agrupado de registros */
SELECT
    t.id_tienda_oltp AS id_tienda,
    t.nombre AS tienda,
    COUNT(*) AS registros_procesados,
    SUM(f.cantidad) AS unidades,
    SUM(f.importe) AS ingresos
FROM bi.FactDetalleVenta f
JOIN bi.DimTienda t
    ON t.tienda_key = f.tienda_key
GROUP BY t.id_tienda_oltp, t.nombre
ORDER BY t.id_tienda_oltp;
GO