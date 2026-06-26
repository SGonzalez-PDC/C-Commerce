# db/

Scripts SQL versionados de la BD que da soporte al bot (servicio `ffa-c-commerce-service`).

Esta carpeta **no se despliega**: `scripts/n8n-sync.js` solo lee `workflows/*.json`,
y el CI (`.github/workflows/deploy-dev.yml`, `deploy-staging.yml`) solo dispara con
`paths: workflows/**`, `envs/<env>.json`, `scripts/**`. Agregar o editar `.sql` aqui
NO redespliega el bot n8n.

## Convencion
- `scripts/NNN_descripcion.sql` — scripts numerados, idempotentes cuando se pueda.
- Los ejecuta una persona, revisando antes. **No** se aplican automaticamente.
- Solo DEV salvo pedido explicito. Nunca correr en STAGE/PROD a la ligera.

## Ejecutar (ejemplo, dev)
```
sqlcmd -S 172.24.0.16,1433 -U <usuario> -P <pass> -C -i db/scripts/001_capabilities_editables_voice_image.sql
```

## Indice
- `001_capabilities_editables_voice_image.sql` — habilita edicion por admin de
  VOICE_RECOGNITION e IMAGE_ANALYSIS en `c_commerce_cat_sales_agent_capability` (DEV_C_COMMERCE).
