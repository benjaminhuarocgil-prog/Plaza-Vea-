SELECT
    'Área de TI' AS Stakeholder,
    (SELECT COUNT(*) FROM operacion.Tienda) AS TotalTiendas,
    (SELECT COUNT(*) FROM operacion.Producto) AS TotalProductos,
    (SELECT COUNT(DISTINCT id_producto)
     FROM operacion.Producto) AS ProductosUnicos;