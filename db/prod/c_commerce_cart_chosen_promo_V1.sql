/*
    c_commerce_cart_chosen_promo_V1.sql

    Soporte para que el cliente ELIJA una sola promo (excluyente) por producto
    en el carrito conversacional del bot.

    - Tabla FFA..c_commerce_cart_chosen_promo: guarda la promo elegida por
      (cart_id, sku). Una fila = la promo que el cliente escogio para ese producto.
    - SP c_commerce_cart_set_chosen_promo_sp_U_V1: resuelve el carrito activo del
      cliente, graba la eleccion y re-aplica promos (apply_promos respeta la eleccion).

    Solo DEV. Idempotente.
*/
USE FFA;
GO

IF OBJECT_ID('FFA.dbo.c_commerce_cart_chosen_promo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.c_commerce_cart_chosen_promo (
        cart_id     UNIQUEIDENTIFIER NOT NULL,
        sku         VARCHAR(20)      NOT NULL,
        codigo      INT              NOT NULL,
        updated_at  DATETIME2        NOT NULL CONSTRAINT DF_ccp_updated DEFAULT SYSDATETIME(),
        CONSTRAINT PK_c_commerce_cart_chosen_promo PRIMARY KEY (cart_id, sku)
    );
END
GO

USE C_COMMERCE;
GO

/*
* PROCEDURE c_commerce_cart_set_chosen_promo_sp_U_V1
* AUTOR: Saul Gonzalez   FECHA: 29-06-2026
* DESCRIPCION: Graba (upsert) la promo elegida por el cliente para un sku del
*   carrito activo y re-aplica las promos. accion 'U' setea; accion 'D' limpia
*   la eleccion del sku (vuelve a auto). Resuelve el carrito ACTIVE por codcliente.
*/
CREATE OR ALTER PROCEDURE dbo.c_commerce_cart_set_chosen_promo_sp_U_V1
    @accion      VARCHAR(5),
    @empresa     VARCHAR(5)   = NULL,
    @codcliente  VARCHAR(25)  = NULL,
    @sku         VARCHAR(20)  = NULL,
    @codigo      INT          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @cart_id UNIQUEIDENTIFIER;
        SELECT TOP 1 @cart_id = h.cart_id
        FROM FFA..ffa_tbl_txn_header_cart h
        WHERE h.empresa = @empresa AND h.codcliente = @codcliente AND h.[status] = 'ACTIVE'
        ORDER BY h.created_at DESC;

        IF @cart_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS ok, 'No hay carrito activo para el cliente.' AS mensaje;
            RETURN;
        END

        IF @accion = 'U'
        BEGIN
            MERGE FFA..c_commerce_cart_chosen_promo AS t
            USING (SELECT @cart_id AS cart_id, @sku AS sku, @codigo AS codigo) AS s
            ON (t.cart_id = s.cart_id AND t.sku = s.sku)
            WHEN MATCHED THEN UPDATE SET codigo = s.codigo, updated_at = SYSDATETIME()
            WHEN NOT MATCHED THEN INSERT (cart_id, sku, codigo) VALUES (s.cart_id, s.sku, s.codigo);
        END
        ELSE IF @accion = 'D'
        BEGIN
            DELETE FROM FFA..c_commerce_cart_chosen_promo
            WHERE cart_id = @cart_id AND (@sku IS NULL OR sku = @sku);
        END

        EXEC dbo.c_commerce_cart_apply_promos_sp_U_V1 @cart_id = @cart_id, @empresa = @empresa, @codcliente = @codcliente;

        SELECT CAST(1 AS BIT) AS ok, @cart_id AS cart_id;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
