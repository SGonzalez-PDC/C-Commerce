# Deploy — Pedido conversacional ISA

## 1. Base de datos (YA aplicada en DEV_C_COMMERCE)
Los SPs ya estan desplegados en DEV_C_COMMERCE (tablas en DEV_FFA). Scripts en esta carpeta `BD/`.
Para STAGING/PROD: ejecutar estos 5 archivos con `sqlcmd -I` (QUOTED_IDENTIFIER ON), en DEV_C_COMMERCE equivalente:
- c_commerce_cart_sp_crud_V1.sql   (al crear carrito replica el portal web Cart/header: resuelve price_list del cliente, direccion y nit del cliente, bodega=tienda, expires_at +7 dias)
- c_commerce_cart_apply_promos_sp_U_V1.sql   (NUEVO: aplica descuento % de promos limpias al carrito; el det SP lo llama. DESPLEGAR ANTES que el det SP)
- c_commerce_cart_det_sp_crud_V1.sql   (guardrail: rechaza sku que no exista en ARTICULO; y llama a c_commerce_cart_apply_promos_sp_U_V1 tras agregar/quitar)
- c_commerce_cart_recommendations_sp_R_V1.sql
- c_commerce_cart_promo_sp_R_V1.sql
- c_commerce_sp_get_cart_summary_V1.sql   (LEFT JOIN a ARTICULO: lineas con sku sin match SE MUESTRAN, total cuadra)

### Seed de precios P100 (datos de prueba)
- seed_precios_P100_test_V1.sql: 3 SKUs sueltos del catalogo de 3502561.
- seed_precios_P100_portafolio188_V1.sql: precia en P100 los 84 SKUs del portafolio
  (perfil 188 / ruta 122) usando el precio de la lista base P1 (fallback: cualquier lista).
  Cobertura final 83/84 (1 SKU sin precio en ninguna lista).

### Limpieza de datos (opcional)
- fix_orphan_cart_lines_V1.sql: detecta/elimina lineas de carrito con sku invalido
  (no existe en ARTICULO) y recalcula el header. PASO 1 es solo SELECT; PASO 2/3
  estan comentados. Una linea basura del cart 3502561 ya se limpio via API.

## 2. Backend
Ya commiteado en rama `develop` (commit "feat: pedido conversacional ..."). 
Deploy = `git push origin develop` → CI despliega a dev. appsettings.json ya trae los nombres de SP.
Nada mas que configurar.

## 3. n8n
Importar/actualizar estos workflows (carpeta `DEV/`):

Tools nuevos:
- ISA Tool - Iniciar Carrito
- ISA Tool - Agregar Producto
- ISA Tool - Quitar Producto
- ISA Tool - Ver Resumen Carrito
- ISA Tool - Promo Producto        (nuevo)
- ISA Tool - Promo Carrito         (nuevo)

Tools actualizados:
- ISA Tool - Recomendaciones       (fix parser + ya devuelve imagen)
- ISA Tool - Generar Link Carrito  (acepta mode=modify)
- ISA Tool - Buscar Productos      (devuelve imagen)

Workflows actualizados:
- ISA Subagente - Pedido           (prompt + 7 tools de carrito/promo)
- IsaCodisa Agent                  (Filtro + Generar Link pasan mode=modify)

### Enlazar tools en n8n (lo unico manual)
En **ISA Subagente - Pedido**, en cada nodo Tool seleccionar su workflow:
- Tool: Iniciar Carrito        → ISA Tool - Iniciar Carrito
- Tool: Agregar Producto       → ISA Tool - Agregar Producto
- Tool: Quitar Producto        → ISA Tool - Quitar Producto
- Tool: Ver Resumen Carrito    → ISA Tool - Ver Resumen Carrito
- Tool: Recomendaciones        → ISA Tool - Recomendaciones
- Tool: Promo Producto         → ISA Tool - Promo Producto
- Tool: Promo Carrito          → ISA Tool - Promo Carrito
(Tool: Buscar Productos ya esta enlazado.)

En **IsaCodisa Agent**: enlazar Tool: Historial si aplica, y verificar que Subagente Pedido apunte al workflow correcto.

## Flujo resultante
1. Cliente arma pedido en el chat (buscar -> agregar/quitar; cada producto muestra su promo).
2. Antes de confirmar: recomendaciones por historial + resumen con bonus aplicado por producto.
3. Bot manda link de checkout en modo modify -> cliente finaliza en la pagina.
4. La pagina dispara notify-cart-ready -> WhatsApp manda resumen oficial con botones (Confirmar / Modificar / Quitar) -> cliente confirma.

## Notas
- El bonus/promo mostrado en el chat es vista previa; el calculo final autoritativo lo aplica C-commerce en el checkout. La formula del chat fue validada contra pedidos reales.
- Imagen, audio: ya funcionaban (SARA tools, Gemini).
