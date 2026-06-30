/*
==============================================================================
 SEED DE PRUEBA (DEV) - promos de BONIFICACION (self) para el cliente 3502561
------------------------------------------------------------------------------
 Crea promos nuevas tipo bonus donde el producto gratis es EL MISMO producto
 (por cada N lleva M gratis), sobre productos que el cliente ve en el chat
 (portafolio 188 + lista P100 + stock). Elegibles: clona la asignacion de la
 promo 22732 (nodos 21/109) que aplica al segmento/geografia del cliente.

 Productos:
   100400040 Te SUPREMO Manzanilla        -> por cada 3 lleva 1 gratis
   100400240 Te SUPREMO Manzanilla Miel    -> por cada 2 lleva 1 gratis
   100400290 Te SUPREMO Rosa de Jamaica     -> por cada 6 lleva 2 gratis

 Idempotente (guarda por nombre). Solo DEV. No toca SPs.
==============================================================================
*/
USE DEV_FFA;
GO

DECLARE @prods TABLE (sku VARCHAR(20), por_cada DECIMAL(18,4), redim INT, nombre VARCHAR(100));
INSERT INTO @prods VALUES
    ('100400040', 3, 1, 'TEST BONUS SELF 3x1 100400040'),
    ('100400240', 2, 1, 'TEST BONUS SELF 2x1 100400240'),
    ('100400290', 6, 2, 'TEST BONUS SELF 6x2 100400290');

DECLARE @sku VARCHAR(20), @pc DECIMAL(18,4), @rd INT, @nom VARCHAR(100);
DECLARE @codigo INT, @cond INT, @asig INT;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT sku, por_cada, redim, nombre FROM @prods;
OPEN cur;
FETCH NEXT FROM cur INTO @sku, @pc, @rd, @nom;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ffa_promocion WHERE empresa = '00010' AND nombre = @nom)
    BEGIN
        INSERT INTO dbo.ffa_promocion
            (empresa, nombre, descripcion, descripcion_publica, fecha_inicio, fecha_fin, estado, codigo_boletin, territorio, cod_cliente)
        VALUES
            ('00010', @nom, @nom, 'Promo de prueba (bonus)', '2026-01-01', '2026-12-31', 1, 'DESCBONI0003', NULL, NULL);
        SET @codigo = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_promocion_articulo (empresa, codigo_promocion, articulo_sku, es_combo)
        VALUES ('00010', @codigo, @sku, 'n');

        INSERT INTO dbo.ffa_condiciones_promocion (empresa, codigo_promocion, apartir_de, hasta, por_cada, isMonetario, orden)
        VALUES ('00010', @codigo, 1, 99, @pc, 0, 1);
        SET @cond = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_beneficios_promocion (empresa, codigo_promocion, tipo_beneficio_id, porcentaje_descuento, articulo_sku, cantidad_redimible, id_condicion_promocion)
        VALUES ('00010', @codigo, 2, 0, @sku, @rd, @cond);

        INSERT INTO dbo.ffa_asignacion_promocion (id_referencia, empresa, status)
        VALUES (@codigo, '00010', 1);
        SET @asig = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_asignacion_promocion_lista_detalle (empresa, id_asignacion, id_referencia, tipo_estructura)
        VALUES ('00010', @asig, 21, 8), ('00010', @asig, 109, 10);
    END
    FETCH NEXT FROM cur INTO @sku, @pc, @rd, @nom;
END
CLOSE cur;
DEALLOCATE cur;
GO
