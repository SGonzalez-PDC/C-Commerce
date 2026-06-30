USE [DEV_C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_cart_sp_crud_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 23-06-2026
* DESCRIPCION: CRUD del encabezado del carrito conversacional de c-commerce (acciones C, GC, R, RS, U, US, D). Las tablas viven en DEV_FFA (referencia cross-db).
* MODIFICACIONES:
*   - 23-06-2026 / Saul Gonzalez: Creacion. Se agrego la accion GC (get-or-create del carrito ACTIVE por codcliente).
*   - 24-06-2026 / Saul Gonzalez: Al crear el carrito se replica el portal web: resuelve price_list del cliente, direccion y nit, bodega=tienda, expires_at +7 dias, y setea tipo_tx y Origen_Facturacion para que el pedido se pueda emitir en el ERP.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_cart_sp_crud_V1]
    @accion             VARCHAR(5),
    @cart_id            UNIQUEIDENTIFIER = NULL,
    @empresa            VARCHAR(10)      = NULL,
    @codcliente         VARCHAR(25)      = NULL,
    @tienda             VARCHAR(10)      = NULL,
    @subtotal           DECIMAL(18,4)    = NULL,
    @discounts_total    DECIMAL(18,4)    = NULL,
    @total              DECIMAL(18,4)    = NULL,
    @status             VARCHAR(20)      = NULL,
    @expires_at         DATETIME2(3)     = NULL,
    @price_list         VARCHAR(20)      = NULL,
    @id_direccion       INT              = NULL,
    @direccion          VARCHAR(MAX)     = NULL,
    @tipo_tx            VARCHAR(5)       = 'FC',
    @origen_facturacion VARCHAR(5)       = '00001'
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Resolver datos del cliente igual que el portal web (Cart/header):
        -- price_list (lista del cliente, fallback P1), direccion y nit del cliente,
        -- bodega = tienda, expiracion +7 dias. Solo al crear carrito.
        DECLARE @price_list_eff VARCHAR(20) = @price_list;
        DECLARE @direccion_eff  VARCHAR(MAX) = @direccion;
        DECLARE @nit_eff        VARCHAR(25)  = NULL;

        IF @accion IN ('C', 'GC')
        BEGIN
            IF @price_list_eff IS NULL
                SELECT TOP 1 @price_list_eff = ISNULL(L.LISTA, 'P1')
                FROM DEV_FFA..clientes s
                LEFT JOIN DEV_FFA..listado_precios L
                    ON s.empresa = L.empresa AND L.estatus = 'S' AND s.lista_precio = L.lista
                WHERE s.empresa = @empresa AND s.codcliente = @codcliente;

            SELECT TOP 1
                @direccion_eff = COALESCE(@direccion_eff, c.direccion),
                @nit_eff       = c.nit
            FROM DEV_FFA..clientes c
            WHERE c.empresa = @empresa AND c.codcliente = @codcliente;
        END

        -- ============================
        -- CREATE
        -- ============================
        IF @accion = 'C'
        BEGIN
            IF @cart_id IS NULL SET @cart_id = NEWID();

            INSERT INTO DEV_FFA..ffa_tbl_txn_header_cart (
                cart_id, codcliente, empresa, tienda, bodega, subtotal, discounts_total, total, [status], created_at, updated_at, expires_at, price_list, id_direccion, direccion, nit, tipo_tx, Origen_Facturacion
            )
            VALUES (
                @cart_id, @codcliente, @empresa, @tienda, @tienda, COALESCE(@subtotal, 0), COALESCE(@discounts_total, 0), COALESCE(@total, 0), COALESCE(@status, 'ACTIVE'), SYSDATETIME(), SYSDATETIME(), COALESCE(@expires_at, DATEADD(DAY, 7, SYSDATETIME())), @price_list_eff, @id_direccion, @direccion_eff, @nit_eff, @tipo_tx, @origen_facturacion
            );

            SELECT @cart_id AS cart_id;
        END

        -- ============================
        -- GET OR CREATE
        -- Devuelve el carrito ACTIVE mas reciente del cliente; si no existe lo crea.
        -- is_new = 1 cuando se creo uno nuevo, 0 cuando se reutilizo el existente.
        -- ============================
        ELSE IF @accion = 'GC'
        BEGIN
            DECLARE @existing_cart_id UNIQUEIDENTIFIER;

            -- Reusa el carrito PENDIENTE del cliente: ACTIVE o ENVIADO_WHATSAPP
            -- (link enviado pero sin pagar/cancelar). Solo se crea uno nuevo si el
            -- ultimo esta en estado terminal (COMPLETED/CANCELLED/DELIVERED) o no hay.
            SELECT TOP 1 @existing_cart_id = h.cart_id
            FROM DEV_FFA..ffa_tbl_txn_header_cart h
            WHERE h.empresa = @empresa
              AND h.codcliente = @codcliente
              AND h.[status] IN ('ACTIVE', 'ENVIADO_WHATSAPP')
            ORDER BY h.created_at DESC;

            IF @existing_cart_id IS NOT NULL
            BEGIN
                -- Si estaba ENVIADO_WHATSAPP (sin confirmar), se reabre como ACTIVE
                -- para que el cliente lo siga viendo y editando.
                UPDATE DEV_FFA..ffa_tbl_txn_header_cart
                SET [status] = 'ACTIVE', updated_at = SYSDATETIME()
                WHERE cart_id = @existing_cart_id AND [status] = 'ENVIADO_WHATSAPP';

                SELECT @existing_cart_id AS cart_id, CAST(0 AS BIT) AS is_new;
            END
            ELSE
            BEGIN
                IF @cart_id IS NULL SET @cart_id = NEWID();

                INSERT INTO DEV_FFA..ffa_tbl_txn_header_cart (
                    cart_id, codcliente, empresa, tienda, bodega, subtotal, discounts_total, total, [status], created_at, updated_at, expires_at, price_list, id_direccion, direccion, nit, tipo_tx, Origen_Facturacion
                )
                VALUES (
                    @cart_id, @codcliente, @empresa, @tienda, @tienda, COALESCE(@subtotal, 0), COALESCE(@discounts_total, 0), COALESCE(@total, 0), 'ACTIVE', SYSDATETIME(), SYSDATETIME(), COALESCE(@expires_at, DATEADD(DAY, 7, SYSDATETIME())), @price_list_eff, @id_direccion, @direccion_eff, @nit_eff, @tipo_tx, @origen_facturacion
                );

                SELECT @cart_id AS cart_id, CAST(1 AS BIT) AS is_new;
            END
        END

        -- ============================
        -- READ (Basic)
        -- ============================
        ELSE IF @accion = 'R'
        BEGIN
            SELECT
                h.cart_id       AS CartId,
                h.codcliente    AS CustomerCode,
                h.empresa       AS Company,
                h.tienda        AS Store,
                h.subtotal      AS Subtotal,
                h.discounts_total AS Discount,
                h.total         AS Total,
                h.[status]      AS [Status],
                h.created_at    AS CreatedDate,
                h.expires_at    AS ExpiryDate
            FROM DEV_FFA..ffa_tbl_txn_header_cart h
            WHERE h.cart_id = @cart_id
              AND h.empresa = @empresa;
        END

        -- ============================
        -- READ SUMMARY
        -- ============================
        ELSE IF @accion = 'RS'
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
                h.expires_at        AS ExpiryDate
            FROM DEV_FFA..ffa_tbl_txn_header_cart h
            WHERE h.cart_id = @cart_id
              AND h.empresa = @empresa;

            -- ResultSet 2: Details
            SELECT
                d.line_id           AS DetailId,
                d.cart_id           AS CartId,
                d.sku               AS ProductCode,
                d.sku               AS ProductName,
                d.qty               AS Quantity,
                d.unit_price        AS UnitPrice,
                d.line_total        AS LineTotal,
                d.line_type         AS LineType
            FROM DEV_FFA..ffa_tbl_txn_detail_cart d
            WHERE d.cart_id = @cart_id;

            -- ResultSet 3: Address
            SELECT TOP 1
                dc.Direccion        AS address,
                dc.zona        AS municipality,
                dc.colonia     AS department
            FROM DEV_FFA..CXC_DireccionCliente dc
            INNER JOIN DEV_FFA..ffa_tbl_txn_header_cart h ON h.codcliente = dc.CodCliente AND h.empresa = dc.Empresa
            WHERE h.cart_id = @cart_id
              AND h.empresa = @empresa
              AND dc.status = 'S'
        END

        -- ============================
        -- UPDATE
        -- ============================
        ELSE IF @accion = 'U'
        BEGIN
            UPDATE DEV_FFA..ffa_tbl_txn_header_cart
            SET codcliente = COALESCE(@codcliente, codcliente),
                tienda = COALESCE(@tienda, tienda),
                subtotal = COALESCE(@subtotal, subtotal),
                discounts_total = COALESCE(@discounts_total, discounts_total),
                total = COALESCE(@total, total),
                [status] = COALESCE(@status, [status]),
                expires_at = COALESCE(@expires_at, expires_at),
                updated_at = SYSDATETIME()
            WHERE cart_id = @cart_id
              AND empresa = @empresa;

            SELECT @@ROWCOUNT AS rows_affected;
        END

        -- ============================
        -- UPDATE STATUS
        -- ============================
        ELSE IF @accion = 'US'
        BEGIN
            IF @status = 'CANCELLED'
            BEGIN
                UPDATE DEV_FFA..ffa_tbl_txn_header_cart
                SET [status] = 'CANCELLED',
                    updated_at = SYSDATETIME()
                WHERE cart_id = @cart_id
                  AND empresa = @empresa
                  AND [status] IN ('ACTIVE', 'READY');
            END
            ELSE
            BEGIN
                UPDATE DEV_FFA..ffa_tbl_txn_header_cart
                SET [status] = @status,
                    updated_at = SYSDATETIME()
                WHERE cart_id = @cart_id
                  AND empresa = @empresa;
            END

            SELECT @@ROWCOUNT AS rows_affected, @status AS [status];
        END

        -- ============================
        -- DELETE
        -- ============================
        ELSE IF @accion = 'D'
        BEGIN
            DELETE FROM DEV_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id;
            DELETE FROM DEV_FFA..ffa_tbl_txn_header_cart WHERE cart_id = @cart_id AND empresa = @empresa;

            SELECT @@ROWCOUNT AS rows_affected;
        END

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
