# Contexto del proyecto — RestaurantMovil (app Wasi)

App Flutter del sistema de restaurantes Wasi. Habla con el backend Spring Boot del
repo `BackendRestaurant`, que se despliega aparte.

## Lo primero que hay que saber

- La app apunta **directo a producción**: `ApiConstants.baseUrl` en
  `lib/core/constants/api_constants.dart`. No hay entorno de pruebas.
- **Un push a `main` aquí no despliega nada**: el APK se compila y distribuye a mano.
  Por eso los clientes suelen andar con una versión más vieja que el servidor, y todo
  cambio de backend debe ser compatible hacia atrás.
- **`flutter analyze` antes de cada push.** Hay ~109 avisos `info` preexistentes
  (`withOpacity`, `unnecessary_const`); lo que no puede haber es `error` ni `warning`
  nuevos en los archivos tocados.

## Convenciones

- Commits y comentarios **en español**; mensajes largos con `git commit -F -`.
- Los comentarios explican **por qué** se hizo así, sobre todo cuando la razón es un
  bug que costó encontrar.
- Navegación: para volver y refrescar se usa `await context.push(...)` + recarga.
  **Nunca `context.go` para volver**: rompe el `await` y fue la causa del bug "la
  mesa sigue libre después de cobrar".
- Los diálogos de confirmación de cobro y de anulación existen para evitar errores
  caros del cajero: no simplificarlos "para ahorrar un toque".

## Diseño visual: dos reglas que ya costaron un bug

- **Todo el texto se escala** por accesibilidad: `app.dart` multiplica por el factor
  elegido (*Normal / Mediano / Grande / Muy grande*), hasta 1.4. Por eso los tamaños
  base se mantienen chicos y consistentes con la pantalla (títulos 15, chips 13,
  secundarios 11), y `escalaTextoDe(context)` se usa **solo** para escalar alturas
  fijas (`mainAxisExtent`, `SizedBox`). Agrandar fuentes "para que se vean" rompe el
  layout en los tamaños grandes.
- **Los chips deben sobrescribir `labelStyle`.** El `chipTheme` define 12 px sin peso
  ni color sobre fondo beige: un `ActionChip` pelado se lava y no se lee. Todos los
  chips de la app fijan `fontWeight: w600` y color explícito.
- Preferir `Wrap` sobre `Row` cuando hay varios elementos en línea: con el texto en
  "Muy grande" bajan de línea en vez de desbordarse.

## Trampa que ya causó una pantalla roja

Un `TextEditingController` creado y destruido **dentro de un diálogo** revienta con
*"A TextEditingController was used after being disposed"*: `showDialog` devuelve el
control al hacer pop, pero la animación de cierre vuelve a dibujar el campo unos
frames después. Los controllers viven en el `State` y se liberan en `dispose()`.

## Módulos que solo ven algunos restaurantes

El backend enciende funciones por restaurante (facturación electrónica, control de
inventario). La app debe **esconder por completo** lo que el negocio no tiene
activado: nada de menús que fallen al tocarlos. El patrón usado es consultar el
estado (por ejemplo `getAlertas(...).habilitado`) y construir la UI a partir de eso.

Cuando un endpoint nuevo puede no estar desplegado todavía, el repositorio lo
absorbe y devuelve vacío en vez de romper la pantalla (ver `InventarioRepository`).

## Dónde está cada cosa

- `features/mesas/presentation/orden_screen.dart` — toma de pedidos y menú del mesero
  (etiquetas de stock: `AGOTADO`, `quedan 3`).
- `features/facturacion/` — cobro, propina, comprobantes e impresión del ticket.
- `features/inventario/` — stock, ingresos, ajustes e historial.
- `features/configuracion/presentation/menu_config_screen.dart` — catálogo: precios,
  disponibilidad, control de stock por plato y **tarifa de IVA** (masiva por
  subcategoría con el ícono `%`, o individual con el chip `IVA —` de cada plato).
- `features/superadmin/` — panel del proveedor: interruptores por restaurante.
- `core/printing/comanda_printer.dart` — comandas y tickets térmicos.

## Qué probar antes de sacar un APK

1. Tomar pedido → enviar a cocina → cobrar → imprimir, en un restaurante **sin**
   módulos nuevos activados: debe verse y funcionar exactamente igual que antes.
2. Probar con el tamaño de texto en **"Muy grande"**, que es donde se rompe el layout.
3. Los caminos de anulación (orden completa e ítem suelto), que es donde se esconden
   los errores de estado.
