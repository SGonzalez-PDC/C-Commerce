/*
==============================================================================
 SEED DE PRUEBA (DEV) - asignacion estilo PROD para promos del cliente 3502561
------------------------------------------------------------------------------
 El detalle de producto de la web (ffa_m_promocion) exige que la promo este
 asignada por GEOGRAFIA (tipo_estructura 7) y, si hay segmentacion (tipo 13),
 que tambien matchee. Patron prod (ej. sku 154200110): tipo 7 -> nodo geografia,
 tipo 13 -> nodo segmentacion.

 Cliente 3502561: geografia = nodo 1, segmentacion = nodo 21.
 A cada promo de prueba se le garantiza:
   tipo_estructura 7  -> id_referencia 1   (geografia)
   tipo_estructura 13 -> id_referencia 21  (segmentacion)

 Promos: 22724, 22727, 22732 (PROM. C-COMMERCE) y 22761/22762/22763 (bonus self).
 Idempotente. Solo DEV.
==============================================================================
*/
USE DEV_FFA;
GO

DECLARE @codigos TABLE (codigo INT);
INSERT INTO @codigos VALUES (22724),(22727),(22732),(22761),(22762),(22763);

DECLARE @cod INT, @asig INT;
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT codigo FROM @codigos;
OPEN cur;
FETCH NEXT FROM cur INTO @cod;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT TOP 1 @asig = id_asignacion FROM dbo.ffa_asignacion_promocion WHERE id_referencia = @cod AND empresa = '00010' ORDER BY id_asignacion;
    IF @asig IS NULL
    BEGIN
        INSERT INTO dbo.ffa_asignacion_promocion (id_referencia, empresa, status) VALUES (@cod, '00010', 1);
        SET @asig = SCOPE_IDENTITY();
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.ffa_asignacion_promocion_lista_detalle WHERE id_asignacion = @asig AND tipo_estructura = 7 AND id_referencia = 1)
        INSERT INTO dbo.ffa_asignacion_promocion_lista_detalle (empresa, id_asignacion, id_referencia, tipo_estructura) VALUES ('00010', @asig, 1, 7);

    IF NOT EXISTS (SELECT 1 FROM dbo.ffa_asignacion_promocion_lista_detalle WHERE id_asignacion = @asig AND tipo_estructura = 13 AND id_referencia = 21)
        INSERT INTO dbo.ffa_asignacion_promocion_lista_detalle (empresa, id_asignacion, id_referencia, tipo_estructura) VALUES ('00010', @asig, 21, 13);

    SET @asig = NULL;
    FETCH NEXT FROM cur INTO @cod;
END
CLOSE cur;
DEALLOCATE cur;
GO
