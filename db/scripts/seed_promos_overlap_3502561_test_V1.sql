/*
==============================================================================
 SEED DE PRUEBA (DEV) - overlap descuento + bonus (estilo Clasica de prod)
------------------------------------------------------------------------------
 Producto searchable del cliente 3502561: 100400440 (Te SUPREMO Jengibre Limon).
 Crea DOS promos elegibles que SOLAPAN en el rango qty 2-6:
   - Descuento 6%
   - Bonus self: 1 gratis por cada 2
 Asi, a qty 4 aplican AMBAS: 6% desc + 2 gratis (igual que Clasica 106401070 en prod).
 Elegibles: asignacion tipo 7 -> geografia nodo 1, tipo 13 -> segmentacion nodo 21.
 Idempotente (por nombre). Solo DEV.
==============================================================================
*/
USE DEV_FFA;
GO

DECLARE @defs TABLE (sku VARCHAR(20), tipo INT, pct DECIMAL(18,4), redim INT, por_cada DECIMAL(18,4), desde DECIMAL(18,4), hasta DECIMAL(18,4), nombre VARCHAR(100));
INSERT INTO @defs VALUES
    ('100400440', 1, 6, 0, 0, 2, 6, 'TEST OVERLAP DESC 6pct 100400440'),
    ('100400440', 2, 0, 1, 2, 2, 6, 'TEST OVERLAP BONUS 1x2 100400440');

DECLARE @sku VARCHAR(20), @tipo INT, @pct DECIMAL(18,4), @redim INT, @pc DECIMAL(18,4), @desde DECIMAL(18,4), @hasta DECIMAL(18,4), @nom VARCHAR(100);
DECLARE @cod INT, @cond INT, @asig INT;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT sku,tipo,pct,redim,por_cada,desde,hasta,nombre FROM @defs;
OPEN cur;
FETCH NEXT FROM cur INTO @sku,@tipo,@pct,@redim,@pc,@desde,@hasta,@nom;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.ffa_promocion WHERE empresa='00010' AND nombre=@nom)
    BEGIN
        INSERT INTO dbo.ffa_promocion (empresa,nombre,descripcion,descripcion_publica,fecha_inicio,fecha_fin,estado,codigo_boletin,territorio,cod_cliente)
        VALUES ('00010',@nom,@nom,'Promo de prueba (overlap)','2026-01-01','2026-12-31',1,'DESCBONI0003',NULL,NULL);
        SET @cod = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_promocion_articulo (empresa,codigo_promocion,articulo_sku,es_combo)
        VALUES ('00010',@cod,@sku,'n');

        INSERT INTO dbo.ffa_condiciones_promocion (empresa,codigo_promocion,apartir_de,hasta,por_cada,isMonetario,orden)
        VALUES ('00010',@cod,@desde,@hasta,@pc,0,1);
        SET @cond = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_beneficios_promocion (empresa,codigo_promocion,tipo_beneficio_id,porcentaje_descuento,articulo_sku,cantidad_redimible,id_condicion_promocion)
        VALUES ('00010',@cod,@tipo,@pct,(CASE WHEN @tipo=2 THEN @sku ELSE NULL END),@redim,@cond);

        INSERT INTO dbo.ffa_asignacion_promocion (id_referencia,empresa,status) VALUES (@cod,'00010',1);
        SET @asig = SCOPE_IDENTITY();

        INSERT INTO dbo.ffa_asignacion_promocion_lista_detalle (empresa,id_asignacion,id_referencia,tipo_estructura)
        VALUES ('00010',@asig,1,7), ('00010',@asig,21,13);
    END
    FETCH NEXT FROM cur INTO @sku,@tipo,@pct,@redim,@pc,@desde,@hasta,@nom;
END
CLOSE cur;
DEALLOCATE cur;
GO
