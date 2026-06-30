/*
==============================================================================
 SEED DE PRUEBA (DEV) - mas promos visibles para el cliente 3502561
------------------------------------------------------------------------------
 Enlaza productos que el cliente SI ve en el chat (portafolio 188 + lista P100 +
 stock) a promociones que YA son ELEGIBLES (estado=1, vigentes, asignadas al
 segmento/geografia del cliente). No crea promos nuevas: solo agrega filas en
 ffa_promocion_articulo. Idempotente (NOT EXISTS). Solo DEV.

 Promos elegibles reutilizadas:
   22732 = 12% descuento (cantidad 1-10)
   22724 = 5% descuento (cantidad 1-10)
   22727 = 5% descuento + bonificacion 2 de DESINFECTANTE FAMILY GUARD (1-10)

 Asignacion de productos:
   100400640 SUPREMO Te Cambio #3            -> 22732 (12%)
   102101310 GUANDY Bote Galleta Waferjumbo  -> 22732 (12%)
   100400010 Te SUPREMO Canela               -> 22724 (5%)
   102101600 GUANDY Cubetaculebrita          -> 22724 (5%)
   102101590 GUANDY Gumy PulpFrasco          -> 22727 (5% + bonus)
==============================================================================
*/
USE DEV_FFA;
GO

INSERT INTO dbo.ffa_promocion_articulo (empresa, codigo_promocion, articulo_sku, es_combo)
SELECT '00010', v.cod, v.sku, 'n'
FROM (VALUES
    (22732, '100400640'),
    (22732, '102101310'),
    (22724, '100400010'),
    (22724, '102101600'),
    (22727, '102101590')
) v(cod, sku)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.ffa_promocion_articulo p
    WHERE p.empresa = '00010' AND p.codigo_promocion = v.cod AND p.articulo_sku = v.sku
);
GO
