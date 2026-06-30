USE [C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_cart_promo_sp_R_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 23-06-2026
* DESCRIPCION: Calcula promociones (descuento % y bonificacion) por carrito (accion CART) o por un sku (accion SKU), leyendo las tablas ffa_promocion / ffa_promocion_articulo / ffa_condiciones_promocion / ffa_beneficios_promocion.
* MODIFICACIONES:
*   - 23-06-2026 / Saul Gonzalez: Creacion.
*   - 26-06-2026 / Saul Gonzalez: Alinear elegibilidad de promos con el portal web (sp_GetBestSellers_V2): solo promos estado=1, dentro de vigencia, con territorio y asignacion (segmentacion/geografia via ffa_asignacion_promocion) que apliquen al cliente. Antes regalaba promos no publicadas.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_cart_promo_sp_R_V1]
    @accion         VARCHAR(5),
    @empresa        VARCHAR(5)       = NULL,
    @cart_id        UNIQUEIDENTIFIER = NULL,
    @sku            VARCHAR(20)      = NULL,
    @qty            DECIMAL(18,4)    = NULL,
    @codcliente     VARCHAR(25)      = NULL,
    @fecha          DATE             = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @fecha IS NULL SET @fecha = CAST(GETDATE() AS DATE);

        -- En modo CART, si no llegan empresa/codcliente, se toman del encabezado del carrito.
        IF @accion = 'CART' AND @cart_id IS NOT NULL
        BEGIN
            SELECT @empresa = COALESCE(@empresa, h.empresa),
                   @codcliente = COALESCE(@codcliente, h.codcliente)
            FROM FFA..ffa_tbl_txn_header_cart h
            WHERE h.cart_id = @cart_id;
        END

        -- ============================================================
        -- Promos ELEGIBLES para este cliente: misma regla que el portal
        -- web (FFA..sp_GetBestSellers_V2, bandera promocion='S').
        -- Solo estos codigos de promocion pueden aplicar/mostrarse.
        -- ============================================================
        DECLARE @territorio_cliente VARCHAR(100) =
            (SELECT territorio FROM FFA..clientes
             WHERE empresa = @empresa AND codcliente = @codcliente);

        ;WITH JerarquiaSegmentacion AS (
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, 0 AS prof
            FROM FFA..FFAniveles n
            INNER JOIN FFA..CLIENTES c ON c.segmentacion_cliente = n.id_nivel
            WHERE c.codcliente = @codcliente AND c.ACTIVO = 'S' AND c.empresa = @empresa AND n.status = 1
            UNION ALL
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, j.prof + 1
            FROM FFA..FFAniveles n
            INNER JOIN JerarquiaSegmentacion j ON n.id_nivel = j.id_nivel_padre
            WHERE n.status = 1 AND j.prof < 10
        ),
        JerarquiaGeografia AS (
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, 0 AS prof
            FROM FFA..FFAniveles n
            INNER JOIN FFA..CLIENTES c ON c.geografia = n.id_nivel
            WHERE c.codcliente = @codcliente AND c.ACTIVO = 'S' AND c.empresa = @empresa AND n.status = 1
            UNION ALL
            SELECT n.id_nivel, n.empresa, n.id_nivel_padre, j.prof + 1
            FROM FFA..FFAniveles n
            INNER JOIN JerarquiaGeografia j ON n.id_nivel = j.id_nivel_padre
            WHERE n.status = 1 AND j.prof < 10
        )
        SELECT DISTINCT f.codigo
        INTO #promos_ok
        FROM FFA..ffa_promocion f
        INNER JOIN FFA..ffa_asignacion_promocion fa
            ON fa.id_referencia = f.codigo AND fa.empresa = f.empresa
        LEFT JOIN FFA..ffa_asignacion_promocion_lista_detalle fad_geo
            ON fad_geo.id_asignacion = fa.id_asignacion AND fad_geo.empresa = fa.empresa
        LEFT JOIN FFA..ffa_asignacion_promocion_lista_detalle fad_seg
            ON fad_seg.id_asignacion = fa.id_asignacion AND fad_seg.empresa = fa.empresa AND fad_seg.tipo_estructura = 13
        LEFT JOIN JerarquiaSegmentacion js
            ON js.id_nivel = fad_seg.id_referencia AND js.empresa = f.empresa
        LEFT JOIN JerarquiaGeografia jg
            ON jg.id_nivel = fad_geo.id_referencia AND jg.empresa = f.empresa
        WHERE f.empresa = @empresa
            AND @fecha BETWEEN CAST(f.fecha_inicio AS DATE) AND CAST(f.fecha_fin AS DATE)
            AND f.estado = 1
            AND (f.territorio IS NULL OR f.territorio = @territorio_cliente)
            AND (
                f.cod_cliente = @codcliente
                OR (f.cod_cliente IS NULL AND jg.id_nivel IS NOT NULL AND (fad_seg.id_referencia IS NULL OR js.id_nivel IS NOT NULL))
            );

        -- Lineas a evaluar (sku, qty, subtotal). En CART salen del carrito; en SKU es una sola.
        CREATE TABLE #lineas (sku VARCHAR(20), qty DECIMAL(18,4), subtotal DECIMAL(18,4));

        IF @accion = 'CART'
        BEGIN
            INSERT INTO #lineas (sku, qty, subtotal)
            SELECT d.sku, d.qty, d.line_subtotal
            FROM FFA..ffa_tbl_txn_detail_cart d
            WHERE d.cart_id = @cart_id
              AND d.line_type = 'SALE';
        END
        ELSE IF @accion = 'SKU'
        BEGIN
            INSERT INTO #lineas (sku, qty, subtotal)
            VALUES (@sku, COALESCE(@qty, 0), 0);
        END

        -- Promociones vigentes que aplican a cada sku, con su mejor condicion segun el pivot
        -- (pivot = cantidad si la condicion no es monetaria, subtotal si lo es).
        SELECT
            l.sku                       AS sku_origen,
            l.qty                       AS qty_origen,
            p.codigo                    AS codigo_promocion,
            p.nombre                    AS promo_nombre,
            COALESCE(p.descripcion_publica, p.descripcion) AS promo_descripcion,
            cnd.apartir_de              AS rango_desde,
            cnd.hasta                   AS rango_hasta,
            cnd.por_cada                AS por_cada,
            bp.tipo_beneficio_id        AS tipo_beneficio,
            bp.porcentaje_descuento     AS porcentaje_descuento,
            bp.articulo_sku             AS bonus_sku,
            ab.DES_SKU                  AS bonus_nombre,
            img.LINK                    AS bonus_imagen,
            bp.cantidad_redimible       AS cantidad_redimible,
            -- Bonus calculado: FLOOR(pivot / por_cada) * cantidad_redimible (tipo 2)
            CASE
                WHEN bp.tipo_beneficio_id = 2 AND cnd.por_cada > 0
                THEN FLOOR((CASE WHEN cnd.isMonetario = 1 THEN l.subtotal ELSE l.qty END) / cnd.por_cada) * bp.cantidad_redimible
                ELSE 0
            END                         AS bonus_cantidad,
            -- Descuento calculado sobre el subtotal de la linea (tipo 1)
            CASE
                WHEN bp.tipo_beneficio_id = 1 AND l.subtotal > 0
                THEN CAST(l.subtotal * bp.porcentaje_descuento / 100.0 AS DECIMAL(18,4))
                ELSE 0
            END                         AS descuento_monto
        FROM #lineas l
        INNER JOIN FFA..ffa_promocion_articulo pa
            ON pa.empresa = @empresa AND pa.articulo_sku = l.sku
        INNER JOIN FFA..ffa_promocion p
            ON p.empresa = pa.empresa
            AND p.codigo = pa.codigo_promocion
            AND p.fecha_inicio <= @fecha
            AND (p.fecha_fin IS NULL OR p.fecha_fin >= @fecha)
            AND (p.cod_cliente IS NULL OR @codcliente IS NULL OR p.cod_cliente = @codcliente)
        -- Solo promos elegibles para el cliente (misma regla que el portal web).
        INNER JOIN #promos_ok pv
            ON pv.codigo = p.codigo
        -- Mejor condicion aplicable segun el pivot (mayor apartir_de que cumple)
        OUTER APPLY (
            SELECT TOP 1 c.condiciones_promocion_id, c.apartir_de, c.hasta, c.por_cada, c.isMonetario
            FROM FFA..ffa_condiciones_promocion c
            WHERE c.empresa = @empresa
              AND c.codigo_promocion = p.codigo
              AND c.apartir_de <= (CASE WHEN c.isMonetario = 1 THEN l.subtotal ELSE l.qty END)
              AND (c.hasta IS NULL OR (CASE WHEN c.isMonetario = 1 THEN l.subtotal ELSE l.qty END) <= c.hasta)
            ORDER BY c.apartir_de DESC
        ) cnd
        -- Beneficios de esa condicion (distintos)
        INNER JOIN FFA..ffa_beneficios_promocion bp
            ON bp.empresa = @empresa
            AND bp.codigo_promocion = p.codigo
            AND (bp.id_condicion_promocion = cnd.condiciones_promocion_id OR cnd.condiciones_promocion_id IS NULL)
        LEFT JOIN FFA..ARTICULO ab
            ON ab.EMPRESA = @empresa AND ab.SKU = bp.articulo_sku
        OUTER APPLY (
            SELECT TOP 1 ri.LINK FROM FFA..RED_IMAGENES ri
            WHERE ri.ID = bp.articulo_sku AND ri.EMPRESA = @empresa AND ri.VIGENTE = 'S'
        ) img
        WHERE cnd.condiciones_promocion_id IS NOT NULL
        GROUP BY
            l.sku, l.qty, p.codigo, p.nombre, COALESCE(p.descripcion_publica, p.descripcion),
            cnd.apartir_de, cnd.hasta, cnd.por_cada, cnd.isMonetario, l.subtotal,
            bp.tipo_beneficio_id, bp.porcentaje_descuento, bp.articulo_sku, ab.DES_SKU, img.LINK, bp.cantidad_redimible
        ORDER BY l.sku, p.codigo;

        DROP TABLE #lineas;
        DROP TABLE #promos_ok;
    END TRY
    BEGIN CATCH
        IF OBJECT_ID('tempdb..#lineas') IS NOT NULL DROP TABLE #lineas;
        IF OBJECT_ID('tempdb..#promos_ok') IS NOT NULL DROP TABLE #promos_ok;
        THROW;
    END CATCH
END;
GO
