/*
==============================================================================
 SEED DE PRUEBA (DEV) - habilita productos con promo para el cliente 3502561
------------------------------------------------------------------------------
 Cliente: 3502561 (FARMACIA REYES) - perfil_portafolio 188 - lista P100.
 Agrega 3 productos con promo activa al portafolio del cliente y les clona
 precio P1 -> P100 para que aparezcan en la busqueda del bot.
 Productos:
   139400100 AUSTRALIAN ENTERA 2200g  -> 25% desc + bonificacion (qty 10-30)
   120800250 Cloro MB 3.785Lx4        -> hasta 20% desc + bonificacion (qty 5-50)
   104300420 Papalina PRINGLES org 37g-> bonificacion x10 -> 1 gratis (qty 10+)
 Idempotente (NOT EXISTS). Solo INSERT, sin borrar ni modificar filas previas.
 Solo DEV.
==============================================================================
*/
USE DEV_FFA;
GO

-- 1) Precio P100 clonado del P1 (mismo precio, unidad y factor)
INSERT INTO dbo.Inv_UniMedArticulo
    (Empresa, Sku, SubPro1, SubPro2, SubPro3, UniMed, lista, Factor_Conversion, MaxDesc,
     Precio, precio1, precio2, precio3, precio4, precio5,
     USUARIOMODIFICO, FECHA_MODIFICACION, Activo, Imagen, [index], margen, feature_articulo)
SELECT
     src.Empresa, src.Sku, src.SubPro1, src.SubPro2, src.SubPro3, src.UniMed, 'P100', src.Factor_Conversion, src.MaxDesc,
     src.Precio, src.precio1, src.precio2, src.precio3, src.precio4, src.precio5,
     'SEED_TEST', GETDATE(), 'S', src.Imagen, src.[index], src.margen, src.feature_articulo
FROM dbo.Inv_UniMedArticulo src
WHERE src.Empresa = '00010'
  AND src.Sku IN ('139400100', '120800250', '104300420')
  AND src.lista = 'P1'
  AND src.Precio > 0
  AND NOT EXISTS (
        SELECT 1 FROM dbo.Inv_UniMedArticulo d
        WHERE d.Empresa = src.Empresa AND d.Sku = src.Sku AND d.UniMed = src.UniMed AND d.lista = 'P100'
  );

-- 2) Portafolio del cliente (perfil 188)
INSERT INTO dbo.parametros_perfil (id_perfil, empresa, id_referencia, tipo, foco)
SELECT 188, '00010', v.sku, NULL, 0
FROM (VALUES ('139400100'), ('120800250'), ('104300420')) v(sku)
WHERE NOT EXISTS (
        SELECT 1 FROM dbo.parametros_perfil p
        WHERE p.id_perfil = 188 AND p.empresa = '00010' AND p.id_referencia = v.sku
  );
GO
