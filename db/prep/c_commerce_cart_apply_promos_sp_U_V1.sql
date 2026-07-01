USE [PREP_C_COMMERCE]
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
* DESCRIPCION: Aplica al carrito conversacional las promos del cliente por linea SALE. Aplica el mejor descuento % + la mejor bonificacion por linea (sin stacking). Solo considera promos ELEGIBLES (misma regla que el portal: estado=1, vigencia, territorio, asignacion segmentacion/geografia). Escribe line_discounts, ffa_tbl_txn_discount_cart y lineas BONUS, y recalcula el encabezado. Idempotente.
* MODIFICACIONES:
*   - 24-06-2026 / Saul Gonzalez: Creacion (solo descuento % limpio).
*   - 24-06-2026 / Saul Gonzalez: Mejor descuento % + mejor bonificacion por linea. Sin stacking.
*   - 29-06-2026 / Saul Gonzalez: Filtro de elegibilidad (estado/territorio/asignacion, igual que el portal) y respeto a la promo elegida por el cliente (excluyente) via c_commerce_cart_chosen_promo.
*   - 30-06-2026 / Saul Gonzalez: Atar cada beneficio a SU condicion (bp.id_condicion_promocion) al elegir el tier por cantidad, igual que c_commerce_cart_promo_sp_R_V1. Antes el bonus se aplicaba con el tier que matcheaba la cantidad aunque el beneficio perteneciera a otro tier (ej. 22727: bonus del tier 11-15 se aplicaba en qty 8).
*   - 30-06-2026 / Saul Gonzalez: Quitar dependencia de c_commerce_cart_chosen_promo (feature elegir-promo sin backend, no usado); siempre aplica auto-mejor. Ya no requiere esa tabla.
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
        FROM PREP_FFA..ffa_tbl_txn_header_cart h
        WHERE h.cart_id = @cart_id;

        -- 0a) Promos ELEGIBLES para el cliente (misma regla que el portal sp_GetBestSellers_V2)
        DECLARE @territorio_cliente VARCHAR(100) =
            (SELECT territorio FROM PREP_FFA..clientes WHERE empresa = @empresa AND codcliente = @codcliente);

        ;WITH JerarquiaSegmentacion AS (
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, 0 AS prof
            FROM PREP_FFA..FFAniveles n INNER JOIN PREP_FFA..CLIENTES c ON c.segmentacion_cliente = n.id_nivel
            WHERE c.codcliente = @codcliente AND c.ACTIVO = 'S' AND c.empresa = @empresa AND n.status = 1
            UNION ALL
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, j.prof + 1
            FROM PREP_FFA..FFAniveles n INNER JOIN JerarquiaSegmentacion j ON n.id_nivel = j.id_nivel_padre
            WHERE n.status = 1 AND j.prof < 10
        ),
        JerarquiaGeografia AS (
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, 0 AS prof
            FROM PREP_FFA..FFAniveles n INNER JOIN PREP_FFA..CLIENTES c ON c.geografia = n.id_nivel
            WHERE c.codcliente = @codcliente AND c.ACTIVO = 'S' AND c.empresa = @empresa AND n.status = 1
            UNION ALL
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, j.prof + 1
            FROM PREP_FFA..FFAniveles n INNER JOIN JerarquiaGeografia j ON n.id_nivel = j.id_nivel_padre
            WHERE n.status = 1 AND j.prof < 10
        )
        SELECT DISTINCT f.codigo
        INTO #promos_ok
        FROM PREP_FFA..ffa_promocion f
        INNER JOIN PREP_FFA..ffa_asignacion_promocion fa ON fa.id_referencia = f.codigo AND fa.empresa = f.empresa
        LEFT JOIN PREP_FFA..ffa_asignacion_promocion_lista_detalle fad_geo ON fad_geo.id_asignacion = fa.id_asignacion AND fad_geo.empresa = fa.empresa
        LEFT JOIN PREP_FFA..ffa_asignacion_promocion_lista_detalle fad_seg ON fad_seg.id_asignacion = fa.id_asignacion AND fad_seg.empresa = fa.empresa AND fad_seg.tipo_estructura = 13
        LEFT JOIN JerarquiaSegmentacion js ON js.id_nivel = fad_seg.id_referencia AND js.empresa = f.empresa
        LEFT JOIN JerarquiaGeografia jg ON jg.id_nivel = fad_geo.id_referencia AND jg.empresa = f.empresa
        WHERE f.empresa = @empresa
            AND @fecha BETWEEN CAST(f.fecha_inicio AS DATE) AND CAST(f.fecha_fin AS DATE)
            AND f.estado = 1
            AND (f.territorio IS NULL OR f.territorio = @territorio_cliente)
            AND (f.cod_cliente = @codcliente OR (f.cod_cliente IS NULL AND jg.id_nivel IS NOT NULL AND (fad_seg.id_referencia IS NULL OR js.id_nivel IS NOT NULL)));


        -- 1) RESET (idempotente): descuentos y lineas BONUS previas
        DELETE FROM PREP_FFA..ffa_tbl_txn_discount_cart WHERE cart_id = @cart_id;
        DELETE FROM PREP_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id AND line_type = 'BONUS';
        UPDATE PREP_FFA..ffa_tbl_txn_detail_cart
        SET line_discounts = 0, line_total = line_subtotal, updated_at = SYSDATETIME()
        WHERE cart_id = @cart_id AND line_type = 'SALE';

        -- 2) DESCUENTO por linea SALE: la promo elegida si la hay; si no, el mejor %.
        DECLARE @aplicar TABLE (line_id INT, codigo INT, nombre VARCHAR(250), pct NUMERIC(18,4), monto NUMERIC(18,4));
        INSERT INTO @aplicar (line_id, codigo, nombre, pct, monto)
        SELECT s.line_id, x.codigo, x.nombre, x.pct, CAST(s.line_subtotal * x.pct / 100.0 AS NUMERIC(18,4))
        FROM (SELECT d.line_id, d.sku, d.qty, d.line_subtotal FROM PREP_FFA..ffa_tbl_txn_detail_cart d WHERE d.cart_id = @cart_id AND d.line_type = 'SALE') s
        CROSS APPLY (
            SELECT TOP 1 p.codigo, p.nombre, bp.porcentaje_descuento AS pct
            FROM PREP_FFA..ffa_promocion_articulo pa
            INNER JOIN PREP_FFA..ffa_promocion p ON p.empresa = pa.empresa AND p.codigo = pa.codigo_promocion
            INNER JOIN PREP_FFA..ffa_beneficios_promocion bp ON bp.empresa = p.empresa AND bp.codigo_promocion = p.codigo AND bp.tipo_beneficio_id = 1 AND bp.porcentaje_descuento > 0
            INNER JOIN PREP_FFA..ffa_condiciones_promocion c ON c.empresa = p.empresa AND c.codigo_promocion = p.codigo
               AND (bp.id_condicion_promocion IS NULL OR c.condiciones_promocion_id = bp.id_condicion_promocion)
               AND c.apartir_de <= (CASE WHEN c.isMonetario = 1 THEN s.line_subtotal ELSE s.qty END)
               AND (c.hasta IS NULL OR (CASE WHEN c.isMonetario = 1 THEN s.line_subtotal ELSE s.qty END) <= c.hasta)
            WHERE pa.empresa = @empresa AND pa.articulo_sku = s.sku
              AND p.codigo IN (SELECT codigo FROM #promos_ok)
            ORDER BY bp.porcentaje_descuento DESC
        ) x
        WHERE x.pct IS NOT NULL;

        UPDATE d SET d.line_discounts = a.monto, d.line_total = d.line_subtotal - a.monto, d.updated_at = SYSDATETIME()
        FROM PREP_FFA..ffa_tbl_txn_detail_cart d INNER JOIN @aplicar a ON a.line_id = d.line_id WHERE d.cart_id = @cart_id;

        INSERT INTO PREP_FFA..ffa_tbl_txn_discount_cart (cart_id, line_id, discount_seq, tipo_forma, cod_promocion, tipo_valor, valor, descuento_calc, id_descuento, observaciones, estado)
        SELECT @cart_id, a.line_id, 1, '1', a.codigo, 1, a.pct, a.monto, CAST(a.codigo AS VARCHAR(100)), a.nombre, 'P' FROM @aplicar a;

        -- 3) BONIFICACION por linea SALE: la promo elegida si la hay; si no, la mejor bonus.
        DECLARE @maxline INT = ISNULL((SELECT MAX(line_id) FROM PREP_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id), 0);
        ;WITH bonus_all AS (
            SELECT d.line_id AS origin_line, bp.articulo_sku AS bonus_sku,
                   FLOOR((CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END) / NULLIF(c.por_cada,0)) * bp.cantidad_redimible AS qty_bonus
            FROM PREP_FFA..ffa_tbl_txn_detail_cart d
            INNER JOIN PREP_FFA..ffa_promocion_articulo pa ON pa.empresa = @empresa AND pa.articulo_sku = d.sku
            INNER JOIN PREP_FFA..ffa_promocion p ON p.empresa = pa.empresa AND p.codigo = pa.codigo_promocion
            INNER JOIN PREP_FFA..ffa_beneficios_promocion bp ON bp.empresa = p.empresa AND bp.codigo_promocion = p.codigo AND bp.tipo_beneficio_id = 2 AND bp.cantidad_redimible > 0
            OUTER APPLY (
                SELECT TOP 1 c.por_cada, c.isMonetario
                FROM PREP_FFA..ffa_condiciones_promocion c
                WHERE c.empresa = p.empresa AND c.codigo_promocion = p.codigo
                  AND (bp.id_condicion_promocion IS NULL OR c.condiciones_promocion_id = bp.id_condicion_promocion)
                  AND c.apartir_de <= (CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END)
                  AND (c.hasta IS NULL OR (CASE WHEN c.isMonetario = 1 THEN d.line_subtotal ELSE d.qty END) <= c.hasta)
                ORDER BY c.apartir_de DESC
            ) c
            WHERE d.cart_id = @cart_id AND d.line_type = 'SALE' AND c.por_cada > 0
              AND p.codigo IN (SELECT codigo FROM #promos_ok)
        ),
        bonus_best AS (
            SELECT origin_line, bonus_sku, qty_bonus,
                   ROW_NUMBER() OVER (PARTITION BY origin_line ORDER BY qty_bonus DESC, bonus_sku) rk
            FROM bonus_all
            WHERE qty_bonus >= 1
        )
        INSERT INTO PREP_FFA..ffa_tbl_txn_detail_cart (cart_id, line_id, sku, line_type, qty, unit_price, line_subtotal, line_discounts, line_total, bonus_origin_line, created_at, updated_at)
        SELECT @cart_id, @maxline + ROW_NUMBER() OVER (ORDER BY origin_line), bonus_sku, 'BONUS', qty_bonus, 0, 0, 0, 0, origin_line, SYSDATETIME(), SYSDATETIME()
        FROM bonus_best WHERE rk = 1;

        -- 4) Recalcular cabecera
        UPDATE h
        SET subtotal = x.sub, discounts_total = x.disc, total = x.tot, updated_at = SYSDATETIME()
        FROM PREP_FFA..ffa_tbl_txn_header_cart h
        CROSS APPLY (
            SELECT ISNULL(SUM(d.line_subtotal), 0) AS sub, ISNULL(SUM(d.line_discounts), 0) AS disc, ISNULL(SUM(d.line_total), 0) AS tot
            FROM PREP_FFA..ffa_tbl_txn_detail_cart d WHERE d.cart_id = @cart_id
        ) x
        WHERE h.cart_id = @cart_id;

        DROP TABLE #promos_ok;
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#promos_ok') IS NOT NULL DROP TABLE #promos_ok;
        THROW;
    END CATCH
END;
GO
