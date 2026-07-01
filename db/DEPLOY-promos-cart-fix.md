# Despliegue — fix de promos del carrito (2026-06-30)

Cambios en los SP del carrito conversacional (DEV verificado y al dia).
Cada ambiente tiene su carpeta con los `.sql` ya prefijados:
`db/dev` (DEV_*), `db/prep` (PREP_*), `db/stage` (STAGE_*), `db/prod` (sin prefijo).

## Que cambio
- `c_commerce_cart_apply_promos_sp_U_V1`: (1) ata cada beneficio a SU condicion
  (`bp.id_condicion_promocion`) al elegir el tier por cantidad — antes el bonus de un
  tier alto se aplicaba en cantidades del tier bajo (ej. 22727: bonus 11-15 se aplicaba
  en qty 8); (2) se quito la dependencia de `c_commerce_cart_chosen_promo` (feature
  "elegir promo" sin backend, no usado) — ahora siempre aplica auto-mejor.
- Los demas SP del carrito se alinean con DEV.

## Que ejecutar POR AMBIENTE (orden libre, son CREATE OR ALTER)

Ejecutar SOLO estos 5 archivos de la carpeta del ambiente:
1. `c_commerce_cart_apply_promos_sp_U_V1.sql`
2. `c_commerce_cart_det_sp_crud_V1.sql`
3. `c_commerce_cart_promo_sp_R_V1.sql`
4. `c_commerce_cart_sp_crud_V1.sql`
5. `c_commerce_sp_get_cart_summary_V1.sql`

NO ejecutar:
- `c_commerce_cart_recommendations_sp_R_V1.sql` — ya identico en prep/stage (correrlo no
  estorba, pero no es necesario).
- `c_commerce_cart_chosen_promo_V1.sql` — feature en pausa; el apply ya no usa la tabla.
  No crear `c_commerce_cart_chosen_promo` en stage/prod.
- `001_capabilities_editables_voice_image.sql` — DEV unicamente (habilita edicion admin
  de voz/imagen). En PREP/STAGE/PROD esta en `is_editable_by_admin=0` a proposito.
  Correrlo solo si se decide habilitar voz/imagen editable en ese ambiente.

## Estado verificado (2026-06-30, server 172.24.0.16)

| Ambiente | BD | Estado |
|----------|----|--------|
| DEV   | DEV_C_COMMERCE / DEV_FFA     | al dia (0 pendientes) — ya ejecutado |
| PREP  | PREP_C_COMMERCE / PREP_FFA   | 5 SP pendientes (los de arriba) |
| STAGE | STAGE_C_COMMERCE / STAGE_FFA | 5 SP pendientes (los de arriba) |
| PROD  | C_COMMERCE / FFA             | no verificable en este server (otro host); correr db/prod al promover |

Soportes (ya existen en PREP_FFA y STAGE_FFA, no hay que tocar): SPs
`ffa_sp_add_cart_line`, `ffa_sp_get_or_create_cart`, `ffa_usp_delete_cart_line`,
`ffa_usp_get_cart`, `ffa_usp_txn_header_cart` y tablas `ffa_tbl_txn_*_cart`.
