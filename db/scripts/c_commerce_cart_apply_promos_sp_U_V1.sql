USE [DEV_C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_cart_apply_promos_sp_U_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 24-06-2026
* DESCRIPCION: Aplica al carrito conversacional TODAS las promos del cliente: el mejor descuento de PORCENTAJE por linea SALE y la MEJOR bonificacion que aplique (un producto gratis) por linea. Escribe line_discounts y filas en ffa_tbl_txn_discount_cart, inserta lineas BONUS (precio 0), y recalcula el encabezado. Idempotente (resetea antes). Solo opera sobre el cart_id indicado.
* MODIFICACIONES:
*   - 24-06-2026 / Saul Gonzalez: Creacion (solo descuento % limpio).
*   - 24-06-2026 / Saul Gonzalez: Aplica el mejor descuento % + la MEJOR bonificacion que aplique por linea (producto+cantidad+cliente). Sin stacking.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_cart_apply_promos_sp_U_V1]
    @cart_id     UNIQUEIDENTIFIER,
    @empresa     VARCHAR(10) = NULL,
    @codcliente  VARCHAR(25) = NULL,
    @fecha       DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @fecha IS NULL SET @fecha = CAST(GETDATE() AS DATE);

        SELECT @empresa = COALESCE(@empresa, h.empresa),
               @codcliente = COALESCE(@codcliente, h.codcliente)
        FROM DEV_FFA..ffa_tbl_txn_header_cart h
        WHERE h.cart_id = @cart_id;

        -- 1) RESET (idempotente): descuentos y lineas BONUS previas
        DELETE FROM DEV_FFA..ffa_tbl_txn_discount_cart WHERE cart_id = @cart_id;
        DELETE FROM DEV_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id AND line_type = 'BONUS';
        UPDATE DEV_FFA..ffa_tbl_txn_detail_cart
        SET line_discounts = 0, line_total = line_subtotal, updated_at = SYSDATETIME()
        WHERE cart_id = @cart_id AND line_type = 'SALE';

        -- 2) DESCUENTO: mejor % por linea SALE (entre TODAS las promos activas del sku)
        DECLARE @aplicar TABLE (line_id INT, codigo INT, nombre VARCHAR(250), pct NUMERIC(18,4), monto NUMERIC(18,4));
        INSERT INTO @aplicar (line_id, codigo, nombre, pct, monto)
        SELECT s.line_id, x.codigo, x.nombre, x.pct, CAST(s.line_subtotal * x.pct / 100.0 AS NUMERIC(18,4))
        FROM (SELECT d.line_id, d.sku, d.qty, d.line_subtotal FROM DEV_FFA..ffa_tbl_txn_detail_cart d WHERE d.cart_id = @cart_id AND d.line_type = 'SALE') s
        CROSS APPLY (
            SELECT TOP 1 p.codigo, p.nombre, bp.porcentaje_descuento AS pct
            FROM DEV_FFA..ffa_promocion_articulo pa
            INNER JOIN DEV_FFA..ffa_promocion p ON p.empresa = pa.empresa AND p.codigo = pa.codigo_promocion
               AND p.fecha_inicio <= @fecha AND (p.fecha_fin IS NULL OR p.fecha_fin >= @fecha)
               AND (p.cod_cliente IS NULL OR @codcliente IS NULL OR p.cod_cliente = @codcliente)
            INNER JOIN DEV_FFA..ffa_beneficios_promocion bp ON bp.empresa = p.empresa AND bp.codigo_promocion = p.codigo AND bp.tipo_beneficio_id = 1 AND bp.porcentaje_descuento > 0
            INNER JOIN DEV_FFA..ffa_condiciones_promocion c ON c.empresa = p.empresa AND c.codigo_promocion = p.codigo
               AND c.apartir_de <= (CASE WHEN c.isMonetario = 1 THEN s.line_subtotal ELSE s.qty END)
               AND (c.hasta IS NULL OR (CASE WHEN c.isMonetario = 1 THEN s.line_subtotal ELSE s.qty END) <= c.hasta)
            WHERE pa.empresa = @empresa AND pa.articulo_sku = s.sku
            ORDER BY bp.porcentaje_descuento DESC
        ) x
        WHERE x.pct IS NOT NULL;

        UPDATE d SET d.line_discounts = a.monto, d.line_total = d.line_subtotal - a.monto, d.updated_at = SYSDATETIME()
        FROM DEV_FFA..ffa_tbl_txn_detail_cart d INNER JOIN @aplicar a ON a.line_id = d.line_id WHERE d.cart_id = @cart_id;

        INSERT INTO DEV_FFA..ffa_tbl_txn_discount_cart (cart_id, line_id, discount_seq, tipo_forma, cod_promocion, tipo_valor, valor, descuento_calc, id_descuento, observaciones, estado)
        SELECT @cart_id, a.line_id, 1, '1', a.codigo, 1, a.pct, a.monto, CAST(a.codigo AS VARCHAR(100)), a.nombre, 'P' FROM @aplicar a;

        -- 3) BONIFICACION: la MEJOR bonus que aplique por linea SALE -> 1 linea BONUS (precio 0)
        DECLARE @maxline INT = ISNULL((SELECT MAX(line_id) FROM DEV_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id), 0);
        ;WITH bonus_all AS (
            -- Solo bonus que SI aplican: producto en la promo, cliente, vigencia, y la condicion
            -- que cumple la cantidad/subtotal de la linea.
            SELECT d.line_id AS origin_line, bp.articulo_sku AS bonus_sku,
                   FLOOR((CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END) / NULLIF(c.por_cada,0)) * bp.cantidad_redimible AS qty_bonus
            FROM DEV_FFA..ffa_tbl_txn_detail_cart d
            INNER JOIN DEV_FFA..ffa_promocion_articulo pa ON pa.empresa = @empresa AND pa.articulo_sku = d.sku
            INNER JOIN DEV_FFA..ffa_promocion p ON p.empresa = pa.empresa AND p.codigo = pa.codigo_promocion
               AND p.fecha_inicio <= @fecha AND (p.fecha_fin IS NULL OR p.fecha_fin >= @fecha)
               AND (p.cod_cliente IS NULL OR @codcliente IS NULL OR p.cod_cliente = @codcliente)
            INNER JOIN DEV_FFA..ffa_beneficios_promocion bp ON bp.empresa = p.empresa AND bp.codigo_promocion = p.codigo AND bp.tipo_beneficio_id = 2 AND bp.cantidad_redimible > 0
            OUTER APPLY (
                SELECT TOP 1 c.por_cada, c.isMonetario
                FROM DEV_FFA..ffa_condiciones_promocion c
                WHERE c.empresa = p.empresa AND c.codigo_promocion = p.codigo
                  AND c.apartir_de <= (CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END)
                  AND (c.hasta IS NULL OR (CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END) <= c.hasta)
                ORDER BY c.apartir_de DESC
            ) c
            WHERE d.cart_id = @cart_id AND d.line_type = 'SALE' AND c.por_cada > 0
        ),
        bonus_best AS (
            -- Una sola bonus por linea: la MEJOR que aplica (mas unidades gratis)
            SELECT origin_line, bonus_sku, qty_bonus,
                   ROW_NUMBER() OVER (PARTITION BY origin_line ORDER BY qty_bonus DESC, bonus_sku) rk
            FROM bonus_all
            WHERE qty_bonus >= 1
        )
        INSERT INTO DEV_FFA..ffa_tbl_txn_detail_cart (cart_id, line_id, sku, line_type, qty, unit_price, line_subtotal, line_discounts, line_total, bonus_origin_line, created_at, updated_at)
        SELECT @cart_id, @maxline + ROW_NUMBER() OVER (ORDER BY origin_line), bonus_sku, 'BONUS', qty_bonus, 0, 0, 0, 0, origin_line, SYSDATETIME(), SYSDATETIME()
        FROM bonus_best WHERE rk = 1;

        -- 4) Recalcular cabecera
        UPDATE h
        SET subtotal = x.sub, discounts_total = x.disc, total = x.tot, updated_at = SYSDATETIME()
        FROM DEV_FFA..ffa_tbl_txn_header_cart h
        CROSS APPLY (
            SELECT ISNULL(SUM(d.line_subtotal), 0) AS sub, ISNULL(SUM(d.line_discounts), 0) AS disc, ISNULL(SUM(d.line_total), 0) AS tot
            FROM DEV_FFA..ffa_tbl_txn_detail_cart d WHERE d.cart_id = @cart_id
        ) x
        WHERE h.cart_id = @cart_id;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
