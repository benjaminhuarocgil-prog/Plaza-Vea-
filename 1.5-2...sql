SELECT
    'Supervisor de caja' AS Stakeholder,
    COUNT(*) AS TotalVentas,
    COUNT(DISTINCT id_venta) AS VentasUnicas
FROM operacion.Venta;
