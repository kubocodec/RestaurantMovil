# Contexto del proyecto — RestaurantMovil (app Wasi)

App Flutter del sistema de restaurantes Wasi. Habla con el backend Spring Boot del
repo `BackendRestaurant`, que se despliega aparte.

## Lo primero que hay que saber

- La app apunta **directo a producción**: `ApiConstants.baseUrl` en
  `lib/core/constants/api_constants.dart`. No hay entorno de pruebas.
- **Un push a `main` aquí no despliega nada**: el APK se compila y distribuye a mano.
  Por eso los clientes suelen andar con una versión más vieja que el servidor, y todo
  cambio de backend debe ser compatible hacia atrás.
- **`flutter analyze` antes de cada push.** Hay ~119 avisos `info` preexistentes
  (`withOpacity`, `unnecessary_const`, llaves de `if`); lo que no puede haber es
  `error` ni `warning` nuevos en los archivos tocados.
- **El SDK es Flutter 3.44 (Dart 3.12), en `~/flutter`, y no está en el PATH**: hay
  que llamarlo por ruta (`/c/Users/KuboC/flutter/bin/flutter`). Si al subir de versión
  `flutter pub get` deja de resolver, **no compila nada y los errores mienten**: con
  `pub get` caído, `package_config.json` queda a medio generar y aparecen cosas como
  `Couldn't resolve the package 'print_bluetooth_thermal'`, `Type 'BluetoothInfo' not
  found` y, por arrastre al inferir `Object?`, errores de `.name` y `.macAdress` en
  `impresoras_config_screen.dart`. **Arregla primero `pub get`; esos errores se van
  solos.** Pasó con `intl ^0.19.0` contra el `intl 0.20.2` que pinea
  `flutter_localizations`.
- Flutter 3.32 renombró `TabBarTheme`, `DialogTheme` y `CardTheme` a `...ThemeData`
  cuando van dentro de `ThemeData` (`core/theme/app_theme.dart`).
- Gradle 8.10.2, AGP 8.7.0 y Kotlin 2.0.0 están por debajo de lo que Flutter va a
  exigir; hoy solo avisa, en la próxima subida frena el build.

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

## El superadmin configura restaurantes que NO son su tenant

`ConfiguracionScreen` recibe `overrideSucursalId` / `overrideRestaurantId` /
`overrideTenantId` cuando se entra desde el panel de superadmin. **Cualquier pantalla
hija tiene que recibir esos ids por parámetro**, nunca sacarlos del `AuthBloc`: el
usuario logueado es el proveedor, no el restaurante que se está configurando.

Ya costó un bug: el selector de tarifa de IVA en `menu_config_screen.dart` leía
`context.read<AuthBloc>().state.user.tenantId` y pedía las tasas del tenant
equivocado, así que **no mostraba ninguna opción** por más que estuvieran activas — y
con un usuario sin `tenantId` el diálogo ni siquiera se abría. Se ve igual que "no
hay datos", que es lo que lo hace difícil de encontrar.

## IVA: el total en pantalla tiene que ser el del comprobante

El resumen del cobro **no puede calcular `subtotal × una sola tasa`**. Cada línea
lleva la tarifa de su plato (`ivaPorcentaje` del detalle de la orden; `null` = hereda
la predeterminada del negocio), y el IVA se agrupa y redondea **por tarifa**, igual
que `FacturaService`. Con la comida al 0% y las bebidas al 15%, calcularlo con una
sola tasa le muestra al cajero un total sin el IVA de las bebidas mientras se cobra
el correcto (el cobro está bien: registra `factura.total`, el del servidor).

En Tasas de IVA, la **estrella** marca la predeterminada y es una decisión aparte del
switch de activo: el negocio mixto necesita las dos tarifas activas y solo una
predeterminada.

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
  **Cortesías** se dan y quitan en el cobro (ícono de regalo por línea; "Regalar toda la
  mesa" solo para admin). Una cuenta en $0 vuelve ya PAGADA del backend: no se llama a
  `registrarPago` (un pago de $0 lo rechaza). El resumen del cobro no suma base ni IVA
  de las líneas en cortesía.
  **Calculadora de vuelto** (`core/settings/ajustes_cobro.dart`): preferencia por cajero,
  guardada en el equipo con clave por usuario y apagada por defecto; se activa en el menú
  lateral. Solo en efectivo. El pago se sigue registrando por el TOTAL (no por lo
  recibido), o el arqueo del cajón se inflaría con el vuelto; lo recibido solo se muestra
  e imprime. No deja cobrar si lo recibido no alcanza.
  **Pregunta de propina**: misma preferencia por cajero (`pedirPropina`), pero ACTIVADA por
  defecto; la apaga el cajero de un local sin propinas.
  Con el teclado abierto el diálogo de cobro se compacta y el vuelto se repite en el
  título (que no se desplaza): en pantallas chicas era imposible verlo al escribir.
- `features/inventario/` — inventario en pestañas: **Insumos** (stock, conteo, merma,
  historial), **Platos** (por unidades, con ingreso y ajuste; y los que van por receta),
  **Compras** y **Proveedores**. `receta_screen.dart` edita la receta de un plato y
  muestra su costo y margen. `data/unidades.dart` convierte kg/lb/L a la unidad base
  (g, ml, u): el backend solo acepta esas tres. Los diálogos de `inventario_dialogos.dart`
  son widgets con estado propio por la trampa del `TextEditingController`.
- `features/configuracion/presentation/menu_config_screen.dart` — catálogo: precios,
  disponibilidad, control de stock por plato (sin control / por unidades / por receta) y **tarifa de IVA** (masiva por
  subcategoría con el ícono `%`, o individual con el chip `IVA —` de cada plato).
- `features/superadmin/` — panel del proveedor: interruptores por restaurante.
- `core/printing/comanda_printer.dart` — comandas y tickets térmicos.

## Qué probar antes de sacar un APK

1. Tomar pedido → enviar a cocina → cobrar → imprimir, en un restaurante **sin**
   módulos nuevos activados: debe verse y funcionar exactamente igual que antes.
2. Probar con el tamaño de texto en **"Muy grande"**, que es donde se rompe el layout.
3. Los caminos de anulación (orden completa e ítem suelto), que es donde se esconden
   los errores de estado.
