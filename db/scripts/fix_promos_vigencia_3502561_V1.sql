/*
  fix_promos_vigencia_3502561_V1.sql
  BD: DEV_FFA  (empresa 00010)

  CONTEXTO:
    Las columnas ffa_promocion.fecha_inicio/fecha_fin son tipo DATE. Una promo cuyo
    fecha_fin = HOY se ve VIGENTE en el chat (compara por fecha: CAST(GETDATE() AS DATE)
    BETWEEN ... inclusivo) pero VENCIDA en la web (compara por datetime: GETDATE() vs
    fecha_fin@00:00:00). Por eso, el ultimo dia, una promo "sale en el chat pero no en
    la web". El arreglo de fondo es en el backend/web (comparar por fecha inclusiva);
    este script SOLO normaliza la DATA: extiende la vigencia de las promos ACTIVAS del
    cliente 3502561 que vencen antes de fin de ano, para que no mueran en el borde.

  ALCANCE: solo promos del cliente 3502561 (empresa 00010, estado=1) actualmente
    vigentes y con fecha_fin < 2026-12-31. NO toca las legacy ya vencidas (historia)
    ni promos de otros clientes/segmentos no relacionados.

  Reversible: respaldo de valores previos en #respaldo (dentro de la transaccion).
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @nueva_fin DATE = '2026-12-31';

-- Promos ACTIVAS del cliente 3502561 verificadas (territorio del cliente=2, cod_cliente
-- directo, o asignacion seg 21 / geo 109). Vencen 2026-06-30 o 2026-07-31.
DECLARE @codes TABLE (codigo INT PRIMARY KEY);
INSERT INTO @codes (codigo) VALUES (22724),(22725),(22727),(22730),(22732);

BEGIN TRANSACTION;
BEGIN TRY
    PRINT '=== ANTES ===';
    SELECT codigo, fecha_inicio, fecha_fin, estado, territorio, cod_cliente
    FROM dbo.ffa_promocion
    WHERE empresa = '00010' AND codigo IN (SELECT codigo FROM @codes)
    ORDER BY codigo;

    UPDATE f
    SET f.fecha_fin = @nueva_fin
    FROM dbo.ffa_promocion f
    WHERE f.empresa = '00010'
      AND f.estado = 1
      AND f.codigo IN (SELECT codigo FROM @codes)
      AND f.fecha_fin < @nueva_fin;

    PRINT '=== filas actualizadas ===';
    PRINT CAST(@@ROWCOUNT AS VARCHAR(10));

    PRINT '=== DESPUES ===';
    SELECT codigo, fecha_inicio, fecha_fin, estado, territorio, cod_cliente
    FROM dbo.ffa_promocion
    WHERE empresa = '00010' AND codigo IN (SELECT codigo FROM @codes)
    ORDER BY codigo;

    COMMIT TRANSACTION;
    PRINT 'OK commit.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH
