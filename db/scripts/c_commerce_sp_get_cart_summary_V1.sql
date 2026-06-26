USE [DEV_C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_sp_get_cart_summary_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 23-06-2026
* DESCRIPCION: Lectura del resumen del carrito (encabezado, detalle y direccion).
* MODIFICACIONES:
*   - 23-06-2026 / Saul Gonzalez: Creacion.
*   - 24-06-2026 / Saul Gonzalez: LEFT JOIN a ARTICULO con COALESCE(nombre, sku) para que las lineas con sku sin match en el catalogo igual se muestren y el total cuadre con lo visible.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_sp_get_cart_summary_V1]
    @accion     VARCHAR(5) = 'R',
    @cart_id    UNIQUEIDENTIFIER,
    @empresa    VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- ============================
        -- READ SUMMARY
        -- ============================
        IF @accion = 'R' OR @accion = 'RS'
        BEGIN
            -- ResultSet 1: Header
            SELECT
                h.cart_id           AS CartId,
                h.codcliente        AS CustomerCode,
                h.empresa           AS Company,
                h.tienda            AS Store,
                h.subtotal          AS Subtotal,
                h.discounts_total   AS Discount,
                h.total             AS Total,
                h.[status]          AS [Status],
                h.created_at        AS CreatedDate,
                h.expires_at        AS ExpiryDate,
                h.direccion         AS Direction,
                h.fecha_entrega_envia AS DeliveryDate
            FROM DEV_FFA..ffa_tbl_txn_header_cart h
            WHERE h.cart_id = @cart_id
              AND (@empresa IS NULL OR h.empresa = @empresa);

            -- ResultSet 2: Details
            SELECT
                d.line_id           AS DetailId,
                d.cart_id           AS CartId,
                d.sku               AS ProductCode,
                COALESCE(a.DES_SKU, d.sku) AS ProductName,
                d.qty               AS Quantity,
                d.unit_price        AS UnitPrice,
                d.line_total        AS LineTotal,
                d.line_type         AS LineType
            FROM DEV_FFA..ffa_tbl_txn_detail_cart d
            INNER JOIN DEV_FFA..ffa_tbl_txn_header_cart h
                ON h.cart_id = d.cart_id
            LEFT JOIN DEV_FFA..ARTICULO AS a
                ON d.sku = a.SKU
                AND a.EMPRESA = h.empresa
                AND a.Activo = 'S'
            WHERE d.cart_id = @cart_id;

            -- ResultSet 3: Address
            SELECT TOP 1
                dc.Direccion        AS address,
                dc.zona        AS municipality,
                dc.colonia     AS department
            FROM DEV_FFA..CXC_DireccionCliente dc
            INNER JOIN DEV_FFA..ffa_tbl_txn_header_cart h ON h.codcliente = dc.CodCliente AND h.empresa = dc.Empresa
            WHERE h.cart_id = @cart_id
              AND (@empresa IS NULL OR h.empresa = @empresa)
              AND dc.status = 'S'
        END
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
