USE [STAGE_C_COMMERCE]
GO
/****** Objeto: StoredProcedure [dbo].[c_commerce_cart_det_sp_crud_V1] Fecha de script: 24/06/2026 16:00:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
* PROCEDURE
* AUTOR: Saul Gonzalez
* FECHA CREACION: 23-06-2026
* DESCRIPCION: CRUD del detalle (lineas) del carrito conversacional (acciones C, R, U, D). Recalcula los totales del encabezado.
* MODIFICACIONES:
*   - 23-06-2026 / Saul Gonzalez: Creacion. Merge por sku en C; delete por sku en D; line_id secuencial por carrito.
*   - 24-06-2026 / Saul Gonzalez: Guardrail que rechaza agregar un sku inexistente en ARTICULO; tras agregar/quitar llama a c_commerce_cart_apply_promos_sp_U_V1 para aplicar descuentos de promo.
*   - 24-06-2026 / Saul Gonzalez: Delete por sku recolecta los line_id (linea + sus bonus) en una variable de tabla antes de borrar, en vez de auto-referenciar la tabla dentro del DELETE.
*   - 24-06-2026 / Saul Gonzalez: En D se borran primero las filas de discount_cart del carrito (FK fk_ffa_tbl_txn_discount_cart_detail) para evitar el conflicto de constraint al borrar lineas con descuento.
*/
CREATE OR ALTER PROCEDURE [dbo].[c_commerce_cart_det_sp_crud_V1]
    @accion             VARCHAR(5),
    @line_id            INT              = NULL,
    @cart_id            UNIQUEIDENTIFIER = NULL,
    @sku                VARCHAR(20)      = NULL,
    @line_type          VARCHAR(10)      = NULL,
    @qty                NUMERIC(18,4)    = NULL,
    @unit_price         NUMERIC(18,4)    = NULL,
    @line_subtotal      NUMERIC(18,4)    = NULL,
    @line_discounts     NUMERIC(18,4)    = NULL,
    @line_total         NUMERIC(18,4)    = NULL,
    @bonus_origin_line  INT              = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- ============================
        -- CREATE
        -- ============================
        IF @accion = 'C'
        BEGIN
            DECLARE @existing_line_id INT;
            DECLARE @line_type_eff VARCHAR(10) = COALESCE(@line_type, 'SALE');
            DECLARE @ret_line_id INT;

            -- Guardrail: el sku debe existir en el catalogo de la empresa del carrito.
            -- Evita lineas huerfanas (sku invalido) que el portal/checkout no resuelve.
            DECLARE @emp_cart VARCHAR(10);
            SELECT @emp_cart = empresa FROM STAGE_FFA..ffa_tbl_txn_header_cart WHERE cart_id = @cart_id;

            IF NOT EXISTS (
                SELECT 1 FROM STAGE_FFA..ARTICULO
                WHERE SKU = @sku AND EMPRESA = @emp_cart AND Activo = 'S'
            )
            BEGIN
                THROW 51000, 'El SKU no existe en el catalogo de la empresa. No se agrego al carrito.', 1;
            END

            -- Merge: si el sku ya existe en el carrito con el mismo line_type, sumar cantidad
            SELECT TOP 1 @existing_line_id = line_id
            FROM STAGE_FFA..ffa_tbl_txn_detail_cart
            WHERE cart_id = @cart_id
              AND sku = @sku
              AND line_type = @line_type_eff
            ORDER BY line_id ASC;

            IF @existing_line_id IS NOT NULL
            BEGIN
                UPDATE STAGE_FFA..ffa_tbl_txn_detail_cart
                SET qty = qty + @qty,
                    unit_price = COALESCE(@unit_price, unit_price),
                    line_subtotal = (qty + @qty) * COALESCE(@unit_price, unit_price),
                    line_total = ((qty + @qty) * COALESCE(@unit_price, unit_price)) - COALESCE(line_discounts, 0),
                    updated_at = SYSDATETIME()
                WHERE cart_id = @cart_id AND line_id = @existing_line_id;

                SET @ret_line_id = @existing_line_id;
            END
            ELSE
            BEGIN
                -- line_id no es IDENTITY y forma parte de la PK (cart_id, line_id):
                -- se asigna secuencialmente por carrito.
                DECLARE @new_line_id INT;
                SELECT @new_line_id = ISNULL(MAX(line_id), 0) + 1
                FROM STAGE_FFA..ffa_tbl_txn_detail_cart
                WHERE cart_id = @cart_id;

                INSERT INTO STAGE_FFA..ffa_tbl_txn_detail_cart (
                    cart_id, line_id, sku, line_type, qty, unit_price, line_subtotal, line_discounts, line_total, bonus_origin_line, created_at, updated_at
                )
                VALUES (
                    @cart_id, @new_line_id, @sku, @line_type_eff, @qty, COALESCE(@unit_price, 0),
                    COALESCE(@line_subtotal, @qty * COALESCE(@unit_price, 0)), COALESCE(@line_discounts, 0),
                    COALESCE(@line_total, (@qty * COALESCE(@unit_price, 0)) - COALESCE(@line_discounts, 0)),
                    @bonus_origin_line, SYSDATETIME(), SYSDATETIME()
                );

                SET @ret_line_id = @new_line_id;
            END

            -- Recalcular totales del encabezado a partir del detalle
            UPDATE h
            SET subtotal = x.sub,
                discounts_total = x.disc,
                total = x.tot,
                updated_at = SYSDATETIME()
            FROM STAGE_FFA..ffa_tbl_txn_header_cart h
            CROSS APPLY (
                SELECT ISNULL(SUM(d.line_subtotal), 0) AS sub,
                       ISNULL(SUM(d.line_discounts), 0) AS disc,
                       ISNULL(SUM(d.line_total), 0) AS tot
                FROM STAGE_FFA..ffa_tbl_txn_detail_cart d
                WHERE d.cart_id = @cart_id
            ) x
            WHERE h.cart_id = @cart_id;

            -- Aplicar descuentos de promo (solo % limpio) al carrito tras agregar
            EXEC dbo.c_commerce_cart_apply_promos_sp_U_V1 @cart_id = @cart_id;

            SELECT @ret_line_id AS line_id;
        END

        -- ============================
        -- READ
        -- ============================
        ELSE IF @accion = 'R'
        BEGIN
            IF @line_id IS NOT NULL AND @cart_id IS NOT NULL
            BEGIN
                SELECT * FROM STAGE_FFA..ffa_tbl_txn_detail_cart 
                WHERE cart_id = @cart_id AND line_id = @line_id;
            END
            ELSE IF @cart_id IS NOT NULL
            BEGIN
                SELECT * FROM STAGE_FFA..ffa_tbl_txn_detail_cart 
                WHERE cart_id = @cart_id;
            END
        END

        -- ============================
        -- UPDATE
        -- ============================
        ELSE IF @accion = 'U'
        BEGIN
            UPDATE STAGE_FFA..ffa_tbl_txn_detail_cart
            SET sku = COALESCE(@sku, sku),
                line_type = COALESCE(@line_type, line_type),
                qty = COALESCE(@qty, qty),
                unit_price = COALESCE(@unit_price, unit_price),
                line_subtotal = COALESCE(@line_subtotal, line_subtotal),
                line_discounts = COALESCE(@line_discounts, line_discounts),
                line_total = COALESCE(@line_total, line_total),
                bonus_origin_line = COALESCE(@bonus_origin_line, bonus_origin_line),
                updated_at = SYSDATETIME()
            WHERE cart_id = @cart_id AND line_id = @line_id;

            SELECT @@ROWCOUNT AS rows_affected;
        END

        -- ============================
        -- DELETE
        -- ============================
        ELSE IF @accion = 'D'
        BEGIN
            -- Limpiar primero las filas hijas en discount_cart (FK fk_ffa_tbl_txn_discount_cart_detail);
            -- apply_promos al final reconstruye los descuentos de las lineas que queden.
            DELETE FROM STAGE_FFA..ffa_tbl_txn_discount_cart WHERE cart_id = @cart_id;

            IF @line_id IS NOT NULL AND @cart_id IS NOT NULL
            BEGIN
                DELETE FROM STAGE_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id AND line_id = @line_id;
            END
            ELSE IF @cart_id IS NOT NULL AND @sku IS NOT NULL
            BEGIN
                -- Quitar producto por sku (incluye sus lineas de bonus asociadas).
                -- Se recolectan primero los line_id a borrar para no referenciar
                -- la misma tabla dentro del DELETE (evita el self-reference en
                -- nombre cross-db de tres partes).
                DECLARE @to_del TABLE (line_id INT PRIMARY KEY);

                INSERT INTO @to_del (line_id)
                SELECT line_id FROM STAGE_FFA..ffa_tbl_txn_detail_cart
                WHERE cart_id = @cart_id AND sku = @sku;

                INSERT INTO @to_del (line_id)
                SELECT d.line_id FROM STAGE_FFA..ffa_tbl_txn_detail_cart d
                WHERE d.cart_id = @cart_id
                  AND d.bonus_origin_line IN (SELECT line_id FROM @to_del)
                  AND d.line_id NOT IN (SELECT line_id FROM @to_del);

                DELETE FROM STAGE_FFA..ffa_tbl_txn_detail_cart
                WHERE cart_id = @cart_id AND line_id IN (SELECT line_id FROM @to_del);
            END
            ELSE IF @cart_id IS NOT NULL
            BEGIN
                DELETE FROM STAGE_FFA..ffa_tbl_txn_detail_cart WHERE cart_id = @cart_id;
            END

            DECLARE @deleted INT = @@ROWCOUNT;

            -- Recalcular totales del encabezado a partir del detalle restante
            UPDATE h
            SET subtotal = x.sub,
                discounts_total = x.disc,
                total = x.tot,
                updated_at = SYSDATETIME()
            FROM STAGE_FFA..ffa_tbl_txn_header_cart h
            CROSS APPLY (
                SELECT ISNULL(SUM(d.line_subtotal), 0) AS sub,
                       ISNULL(SUM(d.line_discounts), 0) AS disc,
                       ISNULL(SUM(d.line_total), 0) AS tot
                FROM STAGE_FFA..ffa_tbl_txn_detail_cart d
                WHERE d.cart_id = @cart_id
            ) x
            WHERE h.cart_id = @cart_id;

            -- Reaplicar descuentos de promo (solo % limpio) tras quitar
            EXEC dbo.c_commerce_cart_apply_promos_sp_U_V1 @cart_id = @cart_id;

            SELECT @deleted AS rows_affected;
        END

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO
