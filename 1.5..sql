USE PlazaVea_G6_1000Productos_50Tiendas;
GO

-- 1. Administrador: ventas e ingresos
SELECT
    'Administrador' AS Stakeholder,
    COUNT(*) AS TotalVentas,
    SUM(CASE WHEN estado = 'Pagada' THEN 1 ELSE 0 END) AS VentasPagadas,
    SUM(CASE WHEN estado = 'Anulada' THEN 1 ELSE 0 END) AS VentasAnuladas
FROM operacion.Venta;

SELECT
    'Administrador - Ingresos' AS Evidencia,
    SUM(f.importe) AS IngresosTotales
FROM bi.FactDetalleVenta f
INNER JOIN operacion.Venta v
    ON v.id_venta = f.id_venta
WHERE v.estado = 'Pagada';
