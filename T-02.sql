SELECT
    dv.id_detalle,
    dv.id_venta,
    dv.id_producto
FROM operacion.DetalleVenta dv
LEFT JOIN operacion.Venta v
    ON dv.id_venta = v.id_venta
LEFT JOIN operacion.Producto p
    ON dv.id_producto = p.id_producto
LEFT JOIN operacion.Tienda t
    ON v.id_tienda = t.id_tienda
WHERE v.id_venta IS NULL
   OR p.id_producto IS NULL
   OR t.id_tienda IS NULL;