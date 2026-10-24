SET STATISTICS TIME ON;
GO

SELECT
    v.id_tienda,
    COUNT(*) AS TotalVentas,
    SUM(CASE WHEN v.estado = 'Pagada' THEN 1 ELSE 0 END) AS VentasPagadas
FROM operacion.Venta v
GROUP BY v.id_tienda;
GO

SET STATISTICS TIME OFF;