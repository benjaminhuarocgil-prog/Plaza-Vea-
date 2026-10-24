USE PlazaVea_G6_1000Productos_50Tiendas;
GO

SELECT
    (SELECT COUNT(*) FROM operacion.Venta) AS TotalVentas,
    (SELECT COUNT(*) FROM operacion.DetalleVenta) AS TotalDetalles;