# Promover de DEV a otro ambiente (staging / prep / prod)

Hay **dos mundos** que se promueven por separado: la **BD** (SPs) y el **n8n** (workflows).
La BD NO se despliega con el repo: los `.sql` se corren a mano. El n8n sí (CI).

## 1. Base de datos (SQL) — manual
Carpetas de scripts ya generadas por ambiente con los nombres de BD correctos:

| Ambiente | Carpeta | BD |
|---|---|---|
| dev | `db/dev/` | `DEV_C_COMMERCE`, `DEV_FFA`, `DEV_SEGURIDAD` |
| staging | `db/staging/` | `STAGE_*` |
| prep | `db/prep/` | `PREP_*` |
| prod | `db/prod/` | `C_COMMERCE`, `FFA`, `SEGURIDAD` (sin prefijo) |

Corre los SPs en este **orden** (en la BD del ambiente):
1. `c_commerce_cart_chosen_promo_V1.sql`   (tabla + setter)
2. `c_commerce_cart_apply_promos_sp_U_V1.sql`
3. `c_commerce_cart_promo_sp_R_V1.sql`
4. `c_commerce_cart_det_sp_crud_V1.sql`
5. `c_commerce_cart_sp_crud_V1.sql`
6. `c_commerce_cart_recommendations_sp_R_V1.sql`
7. `c_commerce_sp_get_cart_summary_V1.sql`
8. `001_capabilities_editables_voice_image.sql`  (UPDATE catalogo VOICE/IMAGE)

Ejemplo (prod):
```
sqlcmd -S <host_prod> -U <user> -P <pass> -C -i db/prod/c_commerce_cart_chosen_promo_V1.sql
... (los 8 en orden)
```

**NO promover** (data de prueba SOLO dev): todo `db/scripts/seed_*.sql`, `fix_orphan_cart_lines_V1.sql`.

## 2. n8n (workflows) — vía CI
Cada ambiente tiene su rama + workflow CI + `envs/<env>.json` (replacements + cred ids):

| Ambiente | Rama | env json | n8n |
|---|---|---|---|
| dev | `develop` | `envs/dev.json` | n8n dev |
| staging | `staging` | `envs/staging.json` | n8n staging |
| prep | `prep` | `envs/prep.json` | n8n staging (mismo) |
| prod | `prod` | `envs/prod.json` | n8n.pdctechco.com |

Para llevar los cambios de dev a, p.ej., staging:
```
git push origin develop:staging     # FF si staging es ancestro; si no, merge/PR
```
El push dispara el CI (`deploy-<env>.yml`), que corre `n8n-sync --env <env>`:
aplica los `replacements` (`.dev→`, `DEV_*→`) y remapea credenciales por nombre.

### Caso PROD (especial)
La rama `prod` NO sale de develop: tiene los workflows **actuales de prod** en forma
dev-canonica. Para llevar cambios de dev a prod: **PR de `develop` (o la rama que sea)
hacia `prod`**, revisar/mergear, y push → `deploy-prod.yml`. El `envs/prod.json` convierte
todo a prod (URLs, BD, phone_number_id, cred ids). empresa/companyId son iguales.

## 3. Backend (ffa-c-commerce-service) — normalmente NO se toca
El backend al desplegar **solo compila/despliega C#**; **NO ejecuta** los `.sql` de
`Sps/V1/` (son solo fuente/referencia). Por eso:
- Los SPs reales viven en la BD y se aplican a mano (paso 1). Que los `.sql` del repo
  backend esten desfasados NO afecta runtime (no se ejecutan); a lo sumo quedan como
  referencia desactualizada.
- El backend SOLO se promueve si cambio **logica C#** (endpoints, DTOs, servicios).
  Nuestro trabajo de promos/carrito fue todo SQL + n8n -> el backend no requiere nada.
- (Opcional/orden) si quieres mantener `Sps/V1/` como documentacion fiel, copia ahi los
  SPs de `db/dev/`, pero no es necesario para que funcione.

## Checklist para promover TODO lo de dev a un ambiente
1. [ ] Correr `db/<env>/*.sql` (los 8, en orden) en la BD del ambiente.
2. [ ] (Si aplica) correr seeds equivalentes — normalmente NO en prod.
3. [ ] Push/PR de la rama -> rama del ambiente (dispara CI n8n).
4. [ ] Verificar run del CI (GitHub Actions).
5. [ ] Backend: SOLO si cambio logica C#. No ejecuta los .sql al desplegar.
6. [ ] Configurar Environment del ambiente en GitHub (N8N_URL + N8N_API_KEY) si no existe.
