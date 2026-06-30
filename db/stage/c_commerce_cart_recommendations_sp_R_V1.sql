USE [STAGE_C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_cart_recommendations_sp_R_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 23-06-2026
* DESCRIPCION: Devuelve productos recomendados para el cliente segun su historial de compras (FACTURA/DETFACT), con el precio de su lista e imagen.
* MODIFICACIONES:
*   - 23-06-2026 / Saul Gonzalez: Creacion.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_cart_recommendations_sp_R_V1]
    @empresa        VARCHAR(5),
    @codcliente     VARCHAR(25),
    @tienda         VARCHAR(5)        = NULL,
    @cart_id        UNIQUEIDENTIFIER = NULL,
    @top            INT              = 5,
    @meses          INT              = 12
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Si no se envia tienda, se toma la del carrito (misma que uso la busqueda de productos).
        IF @tienda IS NULL AND @cart_id IS NOT NULL
        BEGIN
            SELECT @tienda = tienda
            FROM STAGE_FFA..ffa_tbl_txn_header_cart
            WHERE cart_id = @cart_id;
        END

        -- Lista de precios igual que la web (ffa_usp_obtener_precio_sku_ecommerce):
        -- 1) listaprecio del cliente (si existe y esta activa); 2) lista_base de la empresa.
        DECLARE @lista VARCHAR(20);

        SELECT TOP 1 @lista = c.listaprecio
        FROM STAGE_FFA..CLIENTES c
        INNER JOIN STAGE_FFA..LISTADO_PRECIOS lp
            ON lp.empresa = c.empresa AND lp.lista = c.listaprecio
        WHERE c.empresa = @empresa
          AND c.codcliente = @codcliente
          AND c.activo = 'S'
          AND ISNULL(lp.estatus, 'S') = 'S';

        IF @lista IS NULL
            SELECT TOP 1 @lista = e.lista_base FROM STAGE_FFA..EMPRESA e WHERE e.cod_empresa = @empresa;

        -- Productos mas comprados por el cliente en la ventana de historial,
        -- en stock, excluyendo los que ya estan en el carrito actual.
        ;WITH historial AS (
            SELECT
                d.sku                       AS sku,
                SUM(d.cantidad)             AS tot_qty,
                COUNT(DISTINCT f.no_tx)     AS veces,
                MAX(f.fecha)                AS ult_compra
            FROM STAGE_FFA..FACTURA f
            INNER JOIN STAGE_FFA..DETFACT d
                ON d.empresa = f.Empresa
                AND d.tienda = f.Tienda
                AND d.caja   = f.caja
                AND d.no_tx  = f.no_tx
            WHERE f.Empresa = @empresa
              AND f.cliente = @codcliente
              AND f.fecha >= DATEADD(MONTH, -@meses, SYSDATETIME())
            GROUP BY d.sku
        )
        SELECT TOP (@top)
            a.SKU               AS id,
            a.DES_SKU           AS nombre,
            c.des_cat_1         AS categoria,
            m.marcades          AS marca,
            u.des_unimed        AS unidad_medida,
            pr.precio           AS precio,
            ii.EXISTENCIA       AS stock,
            img.LINK            AS imagen,
            h.veces             AS compras_previas,
            h.ult_compra        AS ultima_compra
        FROM historial h
        INNER JOIN STAGE_FFA..ARTICULO a
            ON a.EMPRESA = @empresa AND a.SKU = h.sku AND a.Activo = 'S'
        INNER JOIN STAGE_FFA..CATEGORIA c
            ON c.empresa = a.EMPRESA AND c.cod_cat_1 = a.CATEGORIA
        INNER JOIN STAGE_FFA..MARCAS m
            ON m.empresa = a.EMPRESA AND m.marca = a.marca
        INNER JOIN STAGE_FFA..UNI_MED u
            ON u.EMPRESA = a.EMPRESA AND u.unimed = a.UNIMED
        INNER JOIN (
            SELECT i.EMPRESA, i.SKU, SUM(i.EXISTENCIA) AS EXISTENCIA
            FROM STAGE_FFA..INVENTARIO i
            WHERE i.EMPRESA = @empresa
              AND i.TIENDA = @tienda
            GROUP BY i.EMPRESA, i.SKU
            HAVING SUM(i.EXISTENCIA) > 0
        ) ii ON ii.EMPRESA = a.EMPRESA AND ii.SKU = a.SKU
        -- Precio ESTRICTO a la lista resuelta (igual que la web).
        OUTER APPLY (
            SELECT TOP 1 iu.precio
            FROM STAGE_FFA..Inv_UniMedArticulo iu
            WHERE iu.Empresa = a.EMPRESA
              AND iu.sku = a.SKU
              AND iu.lista = @lista
              AND iu.precio > 0
            ORDER BY iu.unimed
        ) pr
        OUTER APPLY (
            SELECT TOP 1 ri.LINK
            FROM STAGE_FFA..RED_IMAGENES ri
            WHERE ri.ID = a.SKU
              AND ri.EMPRESA = @empresa
              AND ri.VIGENTE = 'S'
        ) img
        WHERE pr.precio IS NOT NULL
          AND (@cart_id IS NULL OR NOT EXISTS (
                    SELECT 1 FROM STAGE_FFA..ffa_tbl_txn_detail_cart dc
                    WHERE dc.cart_id = @cart_id AND dc.sku = a.SKU
              ))
        ORDER BY h.tot_qty DESC, h.ult_compra DESC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
