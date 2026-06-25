# C-Commerce — Workflows n8n (IsaCodisa)

Control de versiones y despliegue de los workflows n8n del bot de C-Commerce.
Una sola fuente (`workflows/`), valores por entorno (`envs/`), despliegue por API
con `scripts/n8n-sync.js`. CI/CD por rama via GitHub Actions.

## Estructura

```
workflows/            Fuente canonica (los .json de n8n, valores DEV).
envs/<env>.json       Config por entorno: reemplazos (URL/BD), credenciales, excludes.
scripts/n8n-sync.js   Sube la carpeta a n8n via API y enlaza las referencias.
.github/workflows/    CI/CD: al push a una rama, despliega su entorno.
.env                  (local, NO se sube) N8N_URL y N8N_API_KEY del entorno.
```

## Modelo

- Se edita SOLO en `workflows/` (valores dev).
- Cada entorno aplica sus reemplazos (`envs/<env>.json`): URL `.dev` -> la del entorno,
  `DEV_FFA` -> `STAGE_FFA`/`PREP_FFA`/`FFA`, etc.
- Las referencias entre workflows (subagentes/tools) se reenlazan por NOMBRE al id real
  del entorno destino, asi quedan cableadas aunque el id sea distinto en cada n8n.
- Las credenciales se remapean por nombre si el env define el id (ver `envs/*.json`).

## Despliegue manual (local)

1. `cp .env.example .env` y llena `N8N_URL` y `N8N_API_KEY` del entorno destino.
2. Previsualiza sin escribir:
   ```
   node scripts/n8n-sync.js --env dev --dry-run
   ```
3. Despliega:
   ```
   node scripts/n8n-sync.js --env dev
   ```
   Opcionales: `--activate` (activa los workflows), `--only "Nombre"` (uno solo).

## Despliegue automatico (CI/CD)

- Push/merge a `develop` -> despliega a dev (`.github/workflows/deploy-dev.yml`).
- En GitHub: Settings -> Environments -> `dev` -> Secrets: `N8N_URL`, `N8N_API_KEY`.
- Para staging/prep/prod: duplicar el workflow de CI cambiando `--env` y el Environment.
  Recomendado: en prod, exigir aprobacion manual en el Environment.

## Reglas

- `.env` nunca se sube (esta en `.gitignore`). Los secretos van en GitHub Environments.
- No editar `workflows/` con valores de staging/prod: eso lo hace el deploy por reemplazo.
- Sin archivos `.bak` en el repo: git es el historial.
