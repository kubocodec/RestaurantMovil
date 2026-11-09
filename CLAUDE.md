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
la predeterminada del negocio), y el IVA se redondea **línea por línea**, igual que
`FacturaService`. Con la comida al 0% y las bebidas al 15%, calcularlo con una sola tasa
le muestra al cajero un total sin el IVA de las bebidas mientras se cobra el correcto
(el cobro está bien: registra `factura.total`, el del servidor).

El cálculo vive en **`core/cobro/desglose_cobro.dart`** y lo usan el cobro y la precuenta:
no duplicarlo. Trabaja en enteros (millonésimas de dólar) porque el precio puede tener
**6 decimales** (precio de menú con IVA ÷ 1.15): base de la línea redondeada a centavos e
IVA sobre la base sin redondear, como el backend y Factuplan.

En Tasas de IVA, la **estrella** marca la predeterminada y es una decisión aparte del
switch de activo: el negocio mixto necesita las dos tarifas activas y solo una
predeterminada.

## Varias cajas en una sucursal: cada cajero cobra en la suya

Antes cada pantalla tomaba `cajas.first`, así que con varias cajas (un evento con 14
cajeros) todos abrían y cobraban en la primera y su cierre mezclaba las ventas de todos.
La regla vive en **`core/caja/caja_actual.dart`** (`CajaActual.resolver`) y la usan Caja,
Cobro, Adelantos y el panel del cajero: **no volver a usar `cajas.first`**.

- **Una sola caja: idéntico a antes** (esa caja y su turno, lo haya abierto quien sea).
- Varias: el cajero cobra solo en el turno que **él** abrió (`usuarioAperturaId`, que el
  backend ya enviaba); elige su caja en Gestión de Caja y queda guardada en el equipo por
  usuario, así el cobro hace una sola consulta. Sin turno propio no cobra.
- El **admin** sin turno propio puede elegir una caja abierta por otro (lista en Caja o
  chips en el cobro): la venta va al cierre de esa caja. Decisión del 2026-11-09.
- No necesitó cambios en el backend: ya permitía un turno abierto por caja.

## Trampa que ya causó una pantalla roja

Un `TextEditingController` creado y destruido **dentro de un diálogo** revienta con
*"A TextEditingController was used after being disposed"*: `showDialog` devuelve el
control al hacer pop, pero la animación de cierre vuelve a dibujar el campo unos
frames después. Los controllers viven en el `State` y se liberan en `dispose()`.

## Módulos que solo ven algunos restaurantes

El backend enciende funciones por restaurante (facturación electrónica, control de
inventario) o por **sucursal** (adelantos de reservas, pedir número de personas; desde
2026-11-08, porque no todos los locales de un negocio trabajan igual). La app debe **esconder por completo** lo que el negocio no tiene
activado: nada de menús que fallen al tocarlos. El patrón usado es consultar el
estado (por ejemplo `getAlertas(...).habilitado`) y construir la UI a partir de eso.

Cuando un endpoint nuevo puede no estar desplegado todavía, el repositorio lo
absorbe y devuelve vacío en vez de romper la pantalla (ver `InventarioRepository` y
`AdelantosRepository.listar`, que responde "no habilitado" si algo falla).

Campos nuevos del backend se leen con valor por defecto (`?? 0`, `?? const []`): un
backend que aún no los envía no debe cambiar nada en pantalla.

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
  **Consumidor final**: dentro de Factura, "Consumidor final (hasta $50)" o "Con datos del
  cliente". Pasado $50 (con propina) se bloquea y se piden los datos; antes de emitir se
  confirma que no se podrá anular. Si la sucursal tiene las notas de venta apagadas
  (`soloFacturas`, interruptor del superadmin) no aparece "Nota de venta" y arranca en
  consumidor final.
  **Pago dividido**: botón en el diálogo de cobro, hasta 3 filas; la última se completa
  sola con lo que falta (contra el total del servidor) y "Sí, cobrar" no se activa hasta
  que cuadre. El vuelto se calcula solo sobre la parte en efectivo. Va por `/pagos/lote`.
  **Adelantos**: "Aplicar adelanto de reserva" en el mismo diálogo. Un cliente puede abonar
  varias veces ($100 y luego $200): se marcan **varios** (al marcar uno se marcan todos los
  del cliente; máximo 7, porque el backend acepta 10 pagos y el dividido usa 3). Se usan del
  más antiguo al más nuevo, cada uno completo hasta cubrir el total (`_repartoAdelantos`);
  solo el último puede quedar a medias y su diferencia se muestra en grande "DEVOLVER AL
  CLIENTE"; los que ya no hacen falta se avisan y siguen pendientes. El cálculo de los
  pagos está en `_armarPagos`. **Precuenta**: ícono en la barra; la pantalla es
  `shared/widgets/precuenta_screen.dart` (solo informa, no cobra).
- `features/adelantos/` — lista de adelantos (pendientes, usados, anulados), nuevo adelanto
  con recibo impreso, cambiar fecha, anular (solo admin). Se entra desde el panel del
  cajero o del admin, solo si el restaurante los tiene activados.
- `features/reportes/` — tarjeta de ventas con **ticket promedio** y **promedio por mesa**
  (sin propinas), y la tarjeta **Cortesías del día**. El detalle del cierre
  (`shared/widgets/cierre_detalle_sheet.dart`) muestra "Incluye propinas", las cortesías
  del turno y los adelantos; `totalCaja` resta lo pagado con adelantos y suma los recibidos
  por transferencia o tarjeta (con 0 en ambos, la fórmula es la de siempre).
- **Resumen del período** (`features/reportes/presentation/resumen_periodo_screen.dart`,
  se entra desde la franja "Resumen del período" de Reportes): período (hoy, 7 días, mes,
  mes anterior, rango) y sucursal o todas. Resultados con ▲/▼ contra el período anterior,
  platos más/menos vendidos (por unidades o dinero), sin ventas, más rentables (solo si hay
  costos), categorías, día y hora, mesa/llevar, métodos de pago, personal y pérdidas. Cada
  sección se esconde si el local no tiene esos datos. Modelo en `data/resumen_periodo_model.dart`.
- `features/inventario/` — inventario en pestañas: **Insumos** (stock, conteo, merma,
  historial), **Platos** (por unidades, con ingreso y ajuste; y los que van por receta),
  **Compras** y **Proveedores**. `receta_screen.dart` edita la receta de un plato y
  muestra su costo y margen. `data/unidades.dart` convierte kg/lb/L a la unidad base
  (g, ml, u): el backend solo acepta esas tres. Los diálogos de `inventario_dialogos.dart`
  son widgets con estado propio por la trampa del `TextEditingController`.
- `features/configuracion/presentation/menu_config_screen.dart` — catálogo: precios,
  disponibilidad, control de stock por plato (sin control / por unidades / por receta) y **tarifa de IVA** (masiva por
  subcategoría con el ícono `%`, o individual con el chip `IVA —` de cada plato).
  Los precios se escriben en `shared/widgets/precio_dialog.dart`: la casilla **"El precio
  incluye IVA"** guarda precio ÷ (1 + tarifa del plato o la vigente) con 6 decimales. Un
  precio ya guardado así se abre con la casilla marcada mostrando el precio con IVA: si se
  mostrara con 2 decimales y se guardara, volvería el descuadre de centavos.
- `features/superadmin/` — panel del proveedor: interruptores por restaurante (menú ⋮ del
  restaurante) y por sucursal (ícono de ajustes de cada sucursal, con su estado a la vista).
- **Personas por mesa** (`orden_screen.dart`, solo si la sucursal tiene `pedirPersonas`): el
  diálogo "Confirmar orden" de una mesa nueva pide "¿Cuántas personas son?" vacío, y "Enviar a
  cocina" no se habilita sin el número. Después se corrige tocando 👥 en la franja de la orden
  (ámbar con "¿?" si no tiene dato). Para llevar nunca lo pide. Reportes muestra "Por
  persona" y "Personas" solo si hubo mesas con el dato.
- **Nota del pedido para llevar** (opcional, sin interruptor): se escribe al confirmar el
  pedido ("Juan, retira 13:30") y va en `observaciones` de la orden, campo que el backend ya
  tenía y la app no usaba (no hizo falta deploy). `OrdenModel.notaPedido` / `lugarConNota` la
  muestran en mesas, cocina, cobro, precuenta y en la comanda. No se edita después.
- **Sin mesas / solo para llevar** (interruptor `soloParaLlevar` de la sucursal, para
  conciertos y barras de evento): `mesas_screen.dart` no muestra mesas, solo "Pedidos" con
  los pendientes de cobro y el botón "Nuevo pedido". En `orden_screen.dart`, si quien
  confirma puede cobrar (cajero o admin), el botón dice "Continuar al cobro" y se abre el
  cobro **encima** de la orden (`push`, no `go` ni replace); al volver, con o sin cobrar,
  se sale como siempre y lo no cobrado queda en la lista. El mesero sigue igual. Con el
  interruptor apagado o un backend que no envía el campo, todo se ve como antes.
- `core/printing/comanda_printer.dart` — comandas y tickets térmicos.

## Qué probar antes de sacar un APK

1. Tomar pedido → enviar a cocina → cobrar → imprimir, en un restaurante **sin**
   módulos nuevos activados: debe verse y funcionar exactamente igual que antes.
2. Probar con el tamaño de texto en **"Muy grande"**, que es donde se rompe el layout.
3. Los caminos de anulación (orden completa e ítem suelto), que es donde se esconden
   los errores de estado.
