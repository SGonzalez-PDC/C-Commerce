/*
    001_capabilities_editables_voice_image.sql

    Habilita la edicion por admin de las capacidades Reconocimiento de voz
    (VOICE_RECOGNITION) y Analisis de imagenes (IMAGE_ANALYSIS) del Sales Agent.

    Motivo: con is_editable_by_admin = 0 el backend fuerza Enabled = false al
    guardar la configuracion (SalesAgentConfigServiceV1.SaveConfigurationAsync),
    por lo que el admin no puede encenderlas desde la pantalla del agente.

    Tabla   : C_COMMERCE.dbo.c_commerce_cat_sales_agent_capability
    Columna : is_editable_by_admin (bit)
    Ambiente: DEV unicamente. NO ejecutar en STAGE/PROD sin pedido explicito.
    Idempotente: solo afecta filas que aun esten en 0.
*/

USE C_COMMERCE;
GO

UPDATE dbo.c_commerce_cat_sales_agent_capability
SET    is_editable_by_admin = 1,
       updated_at           = SYSUTCDATETIME(),
       updated_by           = 'SYSM'
WHERE  capability_code IN ('VOICE_RECOGNITION', 'IMAGE_ANALYSIS')
  AND  is_editable_by_admin = 0;
GO

-- Verificacion
SELECT capability_code, is_editable_by_admin, active, is_deleted
FROM   dbo.c_commerce_cat_sales_agent_capability
ORDER  BY display_order;
GO
