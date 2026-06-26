-- =============================================
-- Fix: lineas huerfanas en carritos (sku que no existe en ARTICULO)
-- Contexto:
--   Algunas lineas de carrito se crearon con un sku invalido (no presente en
--   DEV_FFA..ARTICULO). El SP de summary hacia INNER JOIN a ARTICULO y las
--   escondia, pero el header (recompute por SUM del detalle) si las sumaba,
--   dejando un Total que no cuadraba con los items visibles.
--
--   Solucion de fondo ya aplicada: c_commerce_sp_get_cart_summary_V1 ahora usa
--   LEFT JOIN + COALESCE(nombre, sku) -> las lineas huerfanas SE MUESTRAN y el
--   total siempre cuadra con lo visible.
--
--   Este script limpia los datos historicos: detecta y (opcionalmente) elimina
--   las lineas con sku invalido en carritos ACTIVE y recalcula el header.
--
-- USO:
--   1) Ejecutar PASO 1 (SELECT) para ver que lineas se eliminarian.
--   2) Si esta correcto, descomentar y ejecutar PASO 2 y PASO 3.
--
-- No destructivo por defecto (PASO 2/3 estan comentados).
-- =============================================

USE DEV_C_COMMERCE;
GO

-- ============================================================
-- PASO 1 (DIAGNOSTICO): lineas huerfanas en carritos ACTIVE
-- ============================================================
SELECT
    d.cart_id,
    d.line_id,
    d.sku,
    d.qty,
    d.unit_price,
    d.line_total,
    h.codcliente,
    h.empresa
FROM DEV_FFA..ffa_tbl_txn_detail_cart d
INNER JOIN DEV_FFA..ffa_tbl_txn_header_cart h
    ON h.cart_id = d.cart_id
   AND h.[status] = 'ACTIVE'
LEFT JOIN DEV_FFA..ARTICULO a
    ON a.SKU = d.sku
   AND a.EMPRESA = h.empresa
   AND a.Activo = 'S'
WHERE a.SKU IS NULL
ORDER BY d.cart_id, d.line_id;
GO

-- ============================================================
-- PASO 2 (CORRECCION): eliminar las lineas huerfanas
-- Descomentar para aplicar.
-- ============================================================
-- DELETE d
-- FROM DEV_FFA..ffa_tbl_txn_detail_cart d
-- INNER JOIN DEV_FFA..ffa_tbl_txn_header_cart h
--     ON h.cart_id = d.cart_id
--    AND h.[status] = 'ACTIVE'
-- LEFT JOIN DEV_FFA..ARTICULO a
--     ON a.SKU = d.sku
--    AND a.EMPRESA = h.empresa
--    AND a.Activo = 'S'
-- WHERE a.SKU IS NULL;
-- GO

-- ============================================================
-- PASO 3 (RECALCULO): recomputar header de carritos ACTIVE desde el detalle
-- Descomentar para aplicar (correr despues del PASO 2).
-- ============================================================
-- UPDATE h
-- SET subtotal        = x.sub,
--     discounts_total = x.disc,
--     total           = x.tot,
--     updated_at      = SYSDATETIME()
-- FROM DEV_FFA..ffa_tbl_txn_header_cart h
-- CROSS APPLY (
--     SELECT ISNULL(SUM(d.line_subtotal), 0)  AS sub,
--            ISNULL(SUM(d.line_discounts), 0)  AS disc,
--            ISNULL(SUM(d.line_total), 0)      AS tot
--     FROM DEV_FFA..ffa_tbl_txn_detail_cart d
--     WHERE d.cart_id = h.cart_id
-- ) x
-- WHERE h.[status] = 'ACTIVE';
-- GO
