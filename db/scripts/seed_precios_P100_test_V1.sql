-- =============================================
-- Seed de precios P100 para datos de prueba (empresa 00010)
-- Inserta filas de precio en lista P100 (unimed 00001) para productos que
-- aparecen en el catalogo del cliente 3502561 pero no tenian precio P100.
-- Precio = precio_sugerido (sin IVA) tomado del catalogo.
-- Guard: solo inserta si NO existe ya una fila P100 para ese sku (evita duplicados).
-- Replicado del INSERT manual provisto por el usuario; solo cambia sku y precio.
-- =============================================

USE DEV_FFA;
GO

DECLARE @seed TABLE (Sku VARCHAR(20), Precio DECIMAL(18,4));
INSERT INTO @seed (Sku, Precio) VALUES
    ('100400640', 22.8600),  -- Supremo Te Cambio #3
    ('102101590', 36.2800),  -- Guandy Gumy Pulpfrasco*12*800g
    ('102101600', 34.6100),  -- Guandy Cubetaculebrita
    ('104000530', 15.0000);  -- SARDINA SIRENA TOM200G (producto de prueba de promo BONUS "por cada 3 lleva 1 gratis")

INSERT INTO dbo.Inv_UniMedArticulo
(
    Empresa, Sku, SubPro1, SubPro2, SubPro3, UniMed, lista,
    Factor_Conversion, MaxDesc, Precio, precio1, precio2, precio3, precio4, precio5,
    ROWGUID, rowguid16, USUARIOMODIFICO, FECHA_MODIFICACION, Activo, Imagen,
    [index], margen, feature_articulo
)
SELECT
    '00010', s.Sku, NULL, NULL, NULL, '00001', 'P100',
    1.0000, NULL, s.Precio, NULL, NULL, NULL, NULL, NULL,
    NEWID(), NEWID(), NULL, GETDATE(), NULL, NULL,
    NULL, NULL, NULL
FROM @seed s
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Inv_UniMedArticulo iu
    WHERE iu.Empresa = '00010' AND iu.Sku = s.Sku AND iu.lista = 'P100'
);
GO
