-- =============================================
-- Seed P100 para el portafolio del cliente (perfil 188, ruta 122, empresa 00010).
-- Inserta una fila de precio en lista P100 (unimed 00001) para cada SKU del
-- portafolio que tenga precio en la lista base P1 y aun no tenga P100.
-- Precio P100 = precio de la lista base P1 (ajustable luego si se quiere margen).
-- Guard: NOT EXISTS evita duplicar P100. No toca filas existentes.
-- Replica el formato del INSERT manual provisto por el usuario.
-- =============================================

USE DEV_FFA;
GO

INSERT INTO dbo.Inv_UniMedArticulo
(
    Empresa, Sku, SubPro1, SubPro2, SubPro3, UniMed, lista,
    Factor_Conversion, MaxDesc, Precio, precio1, precio2, precio3, precio4, precio5,
    ROWGUID, rowguid16, USUARIOMODIFICO, FECHA_MODIFICACION, Activo, Imagen,
    [index], margen, feature_articulo
)
SELECT
    '00010', pp.id_referencia, NULL, NULL, NULL, '00001', 'P100',
    1.0000, NULL, p1.precio, NULL, NULL, NULL, NULL, NULL,
    NEWID(), NEWID(), NULL, GETDATE(), NULL, NULL,
    NULL, NULL, NULL
FROM dbo.parametros_perfil pp
CROSS APPLY (
    SELECT TOP 1 iu.precio
    FROM dbo.Inv_UniMedArticulo iu
    WHERE iu.Empresa = '00010' AND iu.sku = pp.id_referencia AND iu.lista = 'P1' AND iu.precio > 0
    ORDER BY iu.unimed
) p1
WHERE pp.empresa = '00010' AND pp.id_perfil = 188
  AND NOT EXISTS (
        SELECT 1 FROM dbo.Inv_UniMedArticulo x
        WHERE x.Empresa = '00010' AND x.sku = pp.id_referencia AND x.lista = 'P100'
  );
GO
