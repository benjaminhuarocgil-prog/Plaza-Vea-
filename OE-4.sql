/* EVIDENCIA OE-04: validación de los datos */
SELECT
    (SELECT COUNT(*) FROM operacion.Producto) AS productos,
    (SELECT COUNT(*) FROM operacion.Tienda) AS tiendas,
    (SELECT COUNT(*) FROM operacion.Venta) AS ventas,
    (SELECT COUNT(*) FROM operacion.Venta
     WHERE estado = 'Pagada') AS ventas_pagadas,
    (SELECT COUNT(*) FROM operacion.Venta
     WHERE estado = 'Anulada') AS ventas_anuladas,
    (SELECT COUNT(*) FROM bi.FactDetalleVenta) AS registros_data_mart;

-- Detectar ventas con referencias inválidas
SELECT v.id_venta
FROM operacion.Venta v
LEFT JOIN operacion.Tienda t
    ON t.id_tienda = v.id_tienda
WHERE t.id_tienda IS NULL;
GO