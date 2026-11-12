# Guía de ejecución — web de escritorio y reportes en Excel

Escrita el 2026-11-12. Está pensada para ejecutarse **por fases y con otro modelo**
(Opus): cada fase se puede hacer en una sesión nueva, porque todo lo que hace falta
saber está aquí o en los `CLAUDE.md`.

| Fase | Qué entrega | Depende de | Tamaño |
|---|---|---|---|
| 0 | Que cada despliegue de la web llegue a los navegadores | nada — **pendiente del OK del usuario** | chica |
| 1 | Maqueta de la web de escritorio (HTML, dos estilos) | nada | mediana |
| 2 | Botón "Descargar Excel" en Reportes e Inventario (web) | nada | mediana-grande |
| 3 | Menú lateral, barra, login y tema de escritorio en Flutter | maqueta aprobada | grande |
| 4 | Panel con gráficos y pantallas pensadas para la PC | fase 3 | varias tareas |
| 5 | Carta digital: fotos y diseños | después, se planifica aparte | — |

Orden pedido por el usuario: maqueta, Excel, y la carta al final. La fase 0 la agregó
quien escribió esta guía al encontrar el problema; va primero porque sin ella nada de
lo demás llega a quien ya abrió la web.

---

## 0. Cómo usar esta guía

1. Lee completo el `CLAUDE.md` de este repo. Sus reglas valen siempre.
2. Lee las secciones 1 a 3 de esta guía y **solo la fase que te tocó**.
3. Haz los pasos en orden. Cada fase termina en una **puerta**: ahí te detienes y le
   muestras al usuario lo que se indica. No sigas a la fase siguiente por tu cuenta.
4. Al cerrar la fase, márcala en la sección 10 y anota ahí lo que decidiste o
   descubriste.
5. Si un paso no se puede cumplir como está escrito, o una decisión de la sección 3
   choca con lo que ves en el código, **detente y pregunta**. No la cambies por otra
   solución: cada una tiene una razón que costó encontrar.

Mensaje para arrancar: *«Lee `docs/plan-web-y-excel/PLAN.md` y ejecuta la Fase N.»*

---

## 1. Reglas para todas las fases

**Despliegue**

- En este repo, **un push a `main` que toque `lib/`, `web/`, `assets/`, `pubspec.*`,
  `deploy/` o el workflow despliega la web a producción** (`wasi.kubocode.com`). Se
  trabaja en una rama por fase. A `main` se llega solo cuando el usuario lo aprueba.
- Commits solo cuando el usuario los pida, en español, con `git commit -F -`.
- `docs/` no dispara el despliegue.
- **El backend no se toca** en ninguna de estas fases. Allá un push a `main`
  reinicia la API de todos los restaurantes, y no hay pruebas ni base de ensayo. Si
  crees que falta un dato del servidor, anótalo en la sección 10 y pregunta.

**El celular no cambia**

- Todo lo nuevo de escritorio va detrás de `kIsWeb` (o de `EscritorioScope`, fase 3).
  En Android, iOS y Windows el árbol de widgets tiene que quedar idéntico al de hoy.
- Nunca `Platform` de `dart:io` ni `dart:html`. Lo que solo existe en el navegador va
  en un archivo aparte con importación condicional
  (`if (dart.library.js_interop)`), o el APK deja de compilar.
- Siguen valiendo las reglas visuales del `CLAUDE.md`: no agrandar fuentes, chips con
  `labelStyle` propio, `Wrap` antes que `Row`, y probar con el texto en "Muy grande".

**Verificación**

- Flutter en este Mac: `/Users/mac/Documents/Developer/flutter/bin/flutter` (no está
  en el PATH; la ruta del `CLAUDE.md` es de otra máquina).
- Antes de dar algo por hecho: `flutter analyze` (el punto de partida son 124 avisos
  `info`; no puede aparecer ningún `error` ni `warning`), `flutter build web --release`
  y `flutter build apk --debug`. El APK se compila aunque la fase sea "solo web": es
  la prueba de que nada de navegador se coló en el móvil.
- Antes de compilar, mira el disco (`df -h /System/Volumes/Data`). Un build limpio de
  Android pide unos 6 GB y el `CLAUDE.md` explica cómo se ve cuando falta.
- Para probar la web en local: compila y sirve `build/web` en `http://localhost:8080`.
  El servidor de producción acepta ese origen (comprobado). La app apunta a
  **producción**: en las pruebas solo se lee. No crees órdenes, cobros ni compras.
- **No escribas contraseñas.** Cuando haga falta entrar, pídele al usuario que inicie
  sesión él en el navegador.
- Di con claridad qué probaste y qué no. "Compila" no es "funciona".

---

## 2. Lo que se comprobó antes de escribir esto (2026-11-12)

**Navegación de la app**

- `lib/core/router/app_router.dart`: go_router 14.8.1, un solo `Navigator`, sin
  `ShellRoute`. Rutas: `/login`, `/superadmin`, `/admin` (`configuracion`, `reportes`),
  `/cajero` (`caja`, `ordenes`, `comprobantes`, `factura/:ordenId`), `/mesero`
  (`mesas`, `para-llevar`, `orden/:mesaId`), `/cocinero`, `/cocina`.
- El `redirect` solo mira si hay sesión: **no comprueba el rol**. En el celular no
  importa; en la web cualquiera puede escribir `/#/admin` en la barra de direcciones.
- Unas 14 pantallas se abren con `Navigator.push` y no tienen dirección propia
  (Inventario, Adelantos, Resumen del período, Receta, Cortesías…). Si se recarga la
  página estando en una, se vuelve al panel.
- Hay 86 `showDialog`, 13 hojas inferiores y 11 selectores de fecha. Revisados uno
  por uno: casi todos cierran con el `context` del propio diálogo, que funciona con
  cualquier estructura. El único que mezcla contextos es la hoja de
  `orden_screen.dart:1366`: cierra con `ctx` y abre la precuenta con el `context` de la
  pantalla. Además, `orden_screen.dart` sale de la orden con `context.canPop()` /
  `context.pop()` en cuatro sitios (líneas 171, 513, 645 y 827).
- El menú de hamburguesa (`AppDrawer`) solo existe en los cuatro paneles
  (`features/dashboard/presentation/*_dashboard.dart`) y navega con `context.go`. Los
  paneles abren sus módulos con `await context.push(...)` y recargan al volver.
- Un único `PopScope` en la app: `receta_screen.dart`, que pregunta antes de salir si
  hay cambios sin guardar.
- `lib/app.dart` limita la app a 1200 px centrados en web y Windows
  (`Capacidades.esPantallaGrande`).

**Aspecto**

- Colores en `core/constants/app_colors.dart`, tema en `core/theme/app_theme.dart`
  (barra superior marrón `#5D4037`, título centrado, pestañas blancas).
- Todo el código pide la fuente `'Poppins'`, pero **`pubspec.yaml` no la incluye**: lo
  que se ve hoy, en el celular y en la web, es la fuente de respaldo (Roboto).
- 33 `AppBar`. Tres llevan blanco escrito a mano (`cocina_screen.dart:144`,
  `mesas_screen.dart:114`, `orden_screen.dart:847`), dos tienen fondo propio
  (`cocina_screen.dart:144`, `cocinero_dashboard.dart:20`) y cuatro tienen `bottom:`
  (cocina, `menu_config_screen.dart:78`, `inventario_screen.dart:35`, mesas). Hay 4 `TabBar`.

**La web publicada**

- `flutter_bootstrap.js` y `main.dart.js` se sirven con
  `Cache-Control: public, max-age=2592000, immutable`, y sus nombres **no llevan hash**.
- El `flutter_service_worker.js` que genera Flutter 3.44 ya no cachea nada: solo se
  desregistra a sí mismo.
- Consecuencia: quien ya abrió la web **sigue con la versión vieja hasta 30 días**
  después de cada despliegue, salvo que fuerce la recarga. La fase 0 lo arregla.
- `web/index.html` no tiene pantalla de carga: se ve en blanco mientras baja la app.

**Datos para el Excel (todo existe ya en el servidor)**

| Dato | Llamada | Rol |
|---|---|---|
| Totales, platos, sin ventas, día y hora, mesa/llevar, métodos de pago, meseros, anuladas | `GET /api/reportes/resumen-periodo` (`sucursalId` o `restaurantId`, `desde`, `hasta`; máximo 366 días) | ADMIN |
| Resumen de un día | `GET /api/reportes/resumen-diario?sucursalId&fecha` | CAJERO, ADMIN |
| Cierres de caja de un día, con movimientos | `GET /api/reportes/cierres-caja?sucursalId&fecha` | ADMIN |
| Comprobantes de un día, con sus pagos y sus platos | `GET /api/facturas/sucursal/{id}?fecha` | CAJERO, ADMIN |
| Cortesías, órdenes anuladas, propinas | `/api/cortesias/reporte`, `/api/reportes/ordenes-anuladas`, `/api/reportes/propinas` (`desde`, `hasta`) | ADMIN |
| Stock de platos | `GET /api/inventario/sucursal/{id}` | CAJERO, ADMIN |
| Insumos, proveedores | `…/sucursal/{id}/insumos`, `…/proveedores` | CAJERO, ADMIN |
| Compras (el listado viene **sin** ítems; cada compra se pide aparte) | `…/sucursal/{id}/compras?desde&hasta`, `…/compras/{id}` | ADMIN |

Todas tienen ya su método en `ReportesRepository`, `FacturacionRepository` e
`InventarioRepository`. Estados de un comprobante: `PENDIENTE`, `PAGADA`, `ANULADA`.

**Paquetes**

- `excel` (el paquete habitual) **no resuelve** en este proyecto: pide `archive ^3` y
  `flutter_native_splash` arrastra `archive ^4`. Simulado con
  `flutter pub add excel --dry-run`. Agregarlo rompería `pub get`, que es la trampa
  que ya describe el `CLAUDE.md`.
- `archive 4.6.0` y `web 1.1.1` ya están en `pubspec.lock` como transitivos.
- `referencia/xlsx_minimo.dart.txt` es un escritor de `.xlsx` ya probado con esas
  versiones: zip íntegro, XML bien formado, vista previa de macOS correcta (colores,
  negritas, encabezado), compila con dart2js y `dart analyze` no reporta nada. **No**
  se probó en Microsoft Excel: en este Mac no hay Excel, LibreOffice ni Numbers.

---

## 3. Decisiones tomadas y por qué

No las reabras sin preguntar.

1. **El menú lateral va junto al `Navigator`, no dentro de un `ShellRoute`.** Se
   arma en el `builder` de `MaterialApp.router`, al lado del navegador único que ya
   existe. Con un `ShellRoute`, las pantallas pasarían a un segundo `Navigator` y los
   diálogos seguirían en el raíz (`showDialog` usa el raíz por defecto). Hoy eso casi
   no rompería nada: de los 99 diálogos y hojas, solo uno mezcla contextos. Pero sí
   cambiaría a qué navegador van las 19 `Navigator.push` y los `context.pop()` de la
   orden, también en el celular. Con el lateral fuera del `Navigator`, la navegación
   queda exactamente igual que hoy en todas las plataformas. El riesgo de regresión
   en el cobro y la anulación es cero, y eso pesa más que la comodidad del `ShellRoute`.
2. **Solo en la web por ahora.** La estructura de escritorio se activa con `kIsWeb` y
   ancho de 1000 px o más. Windows queda como está hasta poder probarlo allí (se cobra
   en el mostrador con esa app), y las tablets no cambian porque usan el APK. Activarlo
   después es cambiar un getter de `Capacidades`.
3. **El Excel se arma en el navegador con lo que el servidor ya entrega.** Así no hay
   despliegue de backend, y se puede probar en local leyendo datos reales.
4. **Escritor de `.xlsx` propio sobre `archive`.** `excel` no resuelve; Syncfusion
   resuelve, pero tiene licencia comercial y esa decisión es del usuario.
5. **El detalle día por día del Excel se limita a 31 días.** Comprobantes, ventas por
   día y cierres se piden un día a la vez. Un mes son unas 90 llamadas; un año serían
   más de mil contra el servidor de producción. Pasado ese límite el archivo sale con
   las hojas de resumen y una nota. Quitar el límite pide un endpoint nuevo: es otra
   conversación.
6. **Primero la maqueta, después Flutter.** El estilo es cuestión de gusto y cambiar
   un HTML cuesta minutos.
7. **El filtro por rol en las rutas va solo en la web**, que es donde hay barra de
   direcciones. En el celular el comportamiento queda igual.

---

## Fase 0 — Que cada despliegue llegue al navegador

**Estado: pendiente del OK del usuario.** Rama: `web/cache-despliegue`.

El problema está descrito en la sección 2. Hay que hacer dos cosas, y hacen falta las
dos: cambiar la caché (para adelante) y cambiarle la dirección a los scripts (para
sacar del apuro a los navegadores que ya guardaron la versión vieja por 30 días).

1. **`deploy/nginx.conf`.** Borra el bloque `location ~* \.(?:js|css|…)$` con
   `max-age=2592000, immutable`. Agrega a nivel de `server`, antes de los `location`:

   ```nginx
   # Flutter NO pone hash en los nombres (main.dart.js, flutter_bootstrap.js,
   # AssetManifest…) y desde 3.4x ya no trae service worker que avise de una
   # versión nueva. Con caché larga, el navegador se quedaba con la app vieja
   # hasta 30 días después de cada despliegue. `no-cache` no es "no guardar":
   # guarda, pero pregunta antes de usar; si no cambió, nginx contesta 304.
   add_header Cache-Control "no-cache";
   ```

   Los tres `location =` con `no-store` se quedan: en nginx, un `location` con su
   propio `add_header` no hereda el del `server`. Corrige también el comentario que
   dice que "los assets llevan hash en el nombre": no es cierto.

2. **`.github/workflows/desplegar-web.yml`.** Después de "Compilar para el navegador"
   y antes de "Preparar el contexto de la imagen":

   ```yaml
         # index.html nunca se cachea, así que cambiarle la dirección a los dos
         # scripts en cada despliegue obliga al navegador a bajarlos de nuevo,
         # aunque los tenga guardados con la caché larga de antes. Los grep
         # hacen fallar el despliegue si Flutter cambia el formato y el sed
         # deja de encontrar el texto.
         - name: Versionar los scripts de arranque
           run: |
             V="${GITHUB_SHA::8}"
             sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=${V}\"|" build/web/index.html
             sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=${V}\"|" build/web/flutter_bootstrap.js
             grep -q "flutter_bootstrap.js?v=${V}" build/web/index.html
             grep -q "main.dart.js?v=${V}" build/web/flutter_bootstrap.js
             echo "Arranque versionado con ${V}"
   ```

3. **Pruébalo en local antes de proponer el merge.** Compila con
   `flutter build web --release --no-web-resources-cdn`, aplica los dos reemplazos a
   mano (en macOS usa `perl -pi -e`, porque `sed -i` es distinto), arma la imagen con
   `deploy/Dockerfile` igual que el workflow y levántala en un puerto libre.
   Comprueba:
   - `curl -sI localhost:PUERTO/main.dart.js` → `Cache-Control: no-cache`.
   - `curl -sI localhost:PUERTO/index.html` → `no-store`.
   - `curl -s localhost:PUERTO/salud` → `ok`.
   - En el navegador: **aparece la pantalla de inicio de sesión** y en la red se pide
     `main.dart.js?v=…` con 200. Esto es lo que prueba que el cargador de Flutter
     acepta la dirección con `?v=`; el `grep` del workflow no lo prueba.
4. Agrega la lección al `CLAUDE.md` (sección "Lo primero que hay que saber").

**Puerta.** Muéstrale al usuario las cabeceras de antes y de después, y pídele el OK
para llevarlo a `main`. Después del despliegue, repite los `curl` contra
`https://wasi.kubocode.com`.

**Ojo.** `canvaskit/` tampoco lleva hash. Un navegador que lo guardó con la caché de
antes lo conserva hasta 30 días: **no subir la versión de Flutter antes del
2026-12-13** sin pensar en eso (un CanvasKit viejo con una app nueva puede fallar).

---

## Fase 1 — Maqueta de la web de escritorio

Rama: `web/maqueta` (solo toca `docs/`). No se escribe Flutter.

**Entrega:** `docs/maqueta-web/index.html`, un solo archivo con CSS y JS dentro, sin
frameworks. Muéstrasela al usuario con la herramienta que tengas para páginas (sigue
sus instrucciones) y deja el archivo en el repo.

**Qué tiene que parecer:** una aplicación web de verdad, a lo ancho de la ventana.
Nada de marco de teléfono ni de app centrada con franjas. Tiene que funcionar bien
entre 1000 y 1920 px de ancho.

### Controles de la maqueta (fuera de la "app")

Una franja fina arriba con:

- **Estilo:** A · Café / B · Claro.
- **Tipografía:** Poppins / Roboto (la de hoy).
- **Pantalla:** las seis de abajo. El menú lateral de la maqueta también navega.

### Estructura común

- **Menú lateral fijo, 248 px.** Arriba, el logo y el nombre del local. Opciones del
  administrador, agrupadas:
  - *(sin título)* Panel
  - **Operación:** Mesas · Por cobrar · Cocina
  - **Caja:** Caja · Comprobantes · Adelantos
  - **Gestión:** Reportes · Inventario · Configuración

  Abajo: inicial y nombre del usuario, su rol, "Preferencias" (tamaño del texto y, si
  cobra, las dos opciones del cobro) y "Cerrar sesión". Inventario y Adelantos solo
  aparecen si el local tiene el módulo: muéstralos, con una nota al pie de la maqueta.
- **Barra superior, 64 px:** título de la pantalla a la izquierda y sus acciones a la
  derecha. Sin hamburguesa.
- **Contenido:** ancho máximo 1240 px, margen de 28 px, tarjetas con radio 14.

### Los dos estilos

Solo cambian los colores; la estructura es la misma, así que construir uno u otro en
Flutter cuesta igual. Usa solo la paleta de `app_colors.dart`:

| | A · Café | B · Claro |
|---|---|---|
| Menú lateral | fondo `#3E2723`, texto blanco al 72 % | fondo blanco, borde derecho `#EDE0D4`, texto `#6D4C41` |
| Opción activa | fondo blanco al 10 %, barra izquierda `#EDE0D4`, texto blanco | fondo `#F5EFE6`, barra izquierda `#5D4037`, texto `#3E2723` en 600 |
| Barra superior | blanca, borde inferior `#EDE0D4`, título 20/600 | mismo fondo que el contenido, sin borde, título 22/700 |
| Contenido | fondo `#FAF7F2`, tarjetas blancas con borde `#EDE0D4` | igual |
| Botón principal | `#5D4037` | `#5D4037` |

Estados: éxito `#388E3C`, aviso `#F57C00`, error `#C62828`, información `#1565C0`.
Mesas: libre `#43A047`, ocupada `#E53935`, reservada `#1E88E5`. Íconos: Material
Symbols Outlined (la app usa los íconos Material "outlined").

### Las seis pantallas

Cada una lleva una etiqueta pequeña con la fase en que llegaría. Datos de ejemplo
creíbles, de un restaurante de prueba; sin marcas reales.

1. **Inicio de sesión** *(fase 3).* Pantalla partida: a la izquierda un panel de marca
   (degradado `#3E2723` → `#5D4037`, logo, una frase y tres ventajas); a la derecha el
   formulario real: Usuario, Contraseña, botón "Ingresar".
2. **Panel del administrador** *(fase 4).* Cuatro indicadores (ventas de hoy con ▲/▼
   contra ayer, mesas ocupadas, órdenes en curso, comprobantes emitidos). Debajo, a
   dos tercios: "Ventas de los últimos 7 días" en barras y la tabla "Órdenes en curso"
   (mesa, mesero, desde, total). En el tercio derecho: "Alertas de inventario" (sin
   stock, por agotarse, insumos por reponer) y "Más vendidos hoy". Todo sale de datos
   que ya existen: no dibujes nada que pida un dato nuevo del servidor.
3. **Reportes del período** *(Excel: fase 2; disposición: fase 4).* Período (Hoy, 7
   días, Este mes, Mes anterior, Rango), sucursal, y en la barra el botón
   **"Descargar Excel"**. Indicadores con ▲/▼, tabla de platos más vendidos, ventas
   por hora, métodos de pago y personal en dos columnas. Incluye como segundo estado
   el **diálogo de exportación**: lista de secciones con casillas, y la barra de
   avance ("Cargando comprobantes · día 12 de 30").
4. **Inventario · Insumos** *(fase 4).* Pestañas Insumos / Platos / Compras /
   Proveedores, buscador, filtro "Solo por reponer", "Nueva compra" y "Descargar
   Excel". Una tabla de verdad: Insumo, Categoría, Stock ("11 botellas + 190 ml"),
   Mínimo, Costo promedio, Valor, Estado.
5. **Mesas con la orden al lado** *(fase 4 o posterior).* Cuadrícula de mesas por
   salón a la izquierda y, a la derecha, la orden de la mesa elegida con sus platos,
   el total y Agregar / Precuenta / Cobrar.
6. **Una pantalla todavía sin rediseñar** *(así se ve tras la fase 3).* La lista de
   Comprobantes tal como es hoy —la del celular— dentro del menú lateral y la barra
   nuevos. Es la pantalla honesta: muestra qué cambia con la fase 3 sola y qué no.

**Puerta.** El usuario elige el estilo (A o B) y la tipografía, y dice qué corregir.
Anótalo en la sección 10. Si elige Poppins, recuérdale lo que implica: hoy la app no
la incluye, y en la fase 3 se cargaría solo en la web para no cambiar el celular.

---

## Fase 2 — Descargar reportes en Excel (solo web)

Rama: `web/excel`. No depende de la maqueta.

**Entrega:** un botón "Descargar Excel" en Resumen del período y otro en Inventario,
visibles solo en la web y solo para ADMIN y SUPER_ADMIN. Baja un `.xlsx` con varias
hojas, encabezados fijos, filtros y totales.

### Pasos

1. **Dependencias.** En `pubspec.yaml`, bajo `dependencies`: `archive: ^4.0.0` y
   `web: ^1.1.0`. Corre `flutter pub get` y mira `git diff pubspec.lock`: solo deben
   pasar de `transitive` a `direct main`, sin cambiar de versión ni mover otros
   paquetes. Si se mueve algo más, detente.
2. **El escritor.** Copia `referencia/xlsx_minimo.dart.txt` a
   `lib/core/exportar/xlsx_minimo.dart`. Ya está probado: no reordenes el XML. El
   orden de los elementos de cada hoja y de `styles.xml` lo fija el formato, y Excel
   rechaza el archivo si se altera. Si necesitas un estilo nuevo, agrégalo **al final**
   del enum `Estilo` y de `<cellXfs>`, en la misma posición, y actualiza `count`.
3. **La descarga.** Tres archivos en `lib/core/exportar/`:
   - `descarga_web.dart`: copia de `referencia/descarga_web.dart.txt`.
   - `descarga_stub.dart`: la misma firma, lanza `UnsupportedError`.
   - `descarga.dart`: `export 'descarga_stub.dart' if (dart.library.js_interop) 'descarga_web.dart';`

   En `Capacidades`: `static bool get descargarArchivos => kIsWeb;`, con su comentario.
4. **Recolector** (`lib/features/reportes/exportar/recolector.dart`). Reúne los datos
   con los repositorios que ya existen; no escribas llamadas HTTP nuevas.
   - Recibe los ids **de la pantalla** (sucursal o todas, restaurante, lista de
     sucursales), nunca del `AuthBloc`: el superadmin exporta restaurantes que no son
     su tenant (ver el `CLAUDE.md`).
   - Las llamadas por día van de a 3 a la vez, no todas juntas. Recorre los días con
     `DateTime(año, mes, día + i)`.
   - Avisa el avance con un callback (`paso`, `hechas`, `total`) y revisa una bandera
     de cancelación entre llamadas.
   - Cada sección en su `try/catch`: si una falla, el libro sale igual y la hoja
     Resumen lo dice ("No se pudo cargar: Cierres de caja del 05/11").
   - Si el período pasa de 31 días, o días × sucursales pasa de 62, no pidas el
     detalle por día y déjalo anotado en Resumen.
   - Inventario solo si `getAlertas(sucursalId).habilitado`.
   - Compras: como mucho 200 por archivo (cada una es una llamada).
5. **Armado del libro** (`libro_reporte.dart`): una función pura
   `List<Hoja> armarLibro(DatosExportacion d)`, sin red ni widgets, para poder probarla.
6. **Diálogo** (`exportar_dialogo.dart`), como `StatefulWidget` propio (por la trampa
   del `TextEditingController` del `CLAUDE.md`): casillas por sección, avance, cancelar
   y el aviso del límite de 31 días. Antes del trabajo pesado, cede un frame
   (`await Future<void>.delayed(Duration.zero)`) para que el indicador se dibuje.
7. **Botones**, con `if (Capacidades.descargarArchivos && esAdmin)`:
   - `resumen_periodo_screen.dart`: acción en el `AppBar`, con el período y la
     sucursal que estén elegidos en pantalla.
   - `inventario_screen.dart`: acción en el `AppBar`; baja solo las hojas de inventario.
8. **Nombre del archivo:** `Wasi - <sucursal o restaurante> - 2026-11-01 a 2026-11-12.xlsx`,
   sin caracteres que el sistema de archivos rechace. Tipo:
   `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

### Las hojas

En todas: título en la fila 1, período y sucursal en la 2, encabezados en la 4
(congelados y con filtro), totales al final. Dinero con `Estilo.dinero`, porcentajes
como fracción (0.15) con `Estilo.porcentaje`, fechas como `DateTime`. Los totales son
fórmulas **con el valor ya calculado** (`Celda(valor, estilo, 'SUBTOTAL(109,…)')`): sin
el valor, Excel muestra 0 en Vista protegida. Las fórmulas van en inglés y con comas.

| Hoja | Fuente | Columnas |
|---|---|---|
| Resumen | resumen-periodo | Indicador, Este período, Período anterior, Variación. Los mismos indicadores y **las mismas cuentas** que la pantalla: usa los getters de `resumen_periodo_model.dart`, no las reescribas. Debajo, las notas (límites, secciones que no cargaron). |
| Platos vendidos | `platos` | Plato, Categoría, Unidades, Ventas con IVA, Ventas sin IVA, Costo unitario, Costo total, Ganancia, Margen, Unidades de cortesía, % de las ventas |
| Categorías | `platos`, agrupado | Categoría, Platos, Unidades, Ventas con IVA, % |
| Platos sin ventas | `sinVenta` | Plato, Categoría, Disponible |
| Día y hora | `porHora`, `diasDelPeriodo` | Día, Hora, Órdenes, Ventas; y un segundo bloque por día de la semana con su promedio por día |
| Mesa y para llevar | `porTipo` | Tipo, Órdenes, Ventas |
| Métodos de pago | `metodosPago` | Método, Monto, % |
| Personal | `meseros` + propinas | Mesero, Órdenes, Ventas, Propinas |
| Ventas por día | resumen-diario, un día a la vez | Fecha, Órdenes, Comprobantes, Mesas cobradas, Personas, Ventas, Descuentos, IVA, Propinas, Neto, Costo, Ganancia, Cortesías (unidades y valor) |
| Comprobantes | facturas por día | Fecha y hora, Tipo, Número, Orden, Lugar, Cliente, Cédula/RUC, Subtotal, Descuento, Base 0 %, Base gravada, IVA, Propina, Total, Formas de pago, Cajero, Estado, Estado SRI, Autorización, Cortesía |
| Detalle de lo vendido | `items` de cada comprobante | Fecha y hora, Comprobante, Orden, Lugar, Plato, Cantidad, Subtotal, Cortesía, Estado del comprobante |
| Cierres de caja | cierres-caja por día | Fecha, Caja, Abrió, Cerró, Apertura, Cierre, Monto inicial, Ventas, Ventas en efectivo, Ingresos, Egresos, Esperado, Contado, Diferencia, Comprobantes, Propinas, Observaciones |
| Movimientos de caja | `ingresos` y `egresos` de cada cierre | Fecha, Caja, Tipo, Concepto, Monto, Usuario |
| Cortesías | cortesias/reporte | Fecha, Orden, Lugar, Plato, Cantidad, Valor, Motivo, Autorizó, Cobrada |
| Órdenes anuladas | ordenes-anuladas | lo mismo que muestra `ordenes_anuladas_screen.dart` |
| Stock de insumos | insumos (con inactivos) | Insumo, Categoría, Unidad, Stock, Stock en su presentación ("11 botellas + 190 ml", con `unidades.dart`), Mínimo, Costo promedio, Valor del stock, Estado, Activo |
| Stock de platos | inventario de la sucursal | Plato, Categoría, Subcategoría, Control, Stock, Mínimo, Estado, Disponible |
| Compras | compras + cada compra | Fecha, Proveedor, Documento, Insumo, Cantidad, Unidad, Costo unitario, Subtotal, Registró, Nota |
| Proveedores | proveedores | Nombre, RUC, Teléfono, Correo, Activo |

Reglas de las hojas:

- Con "todas las sucursales", las hojas por sucursal llevan una columna **Sucursal**.
- **Esconde lo que el local no usa** (regla del `CLAUDE.md`): sin inventario no hay
  hojas de inventario; sin costos no hay columnas de costo ni de ganancia; sin
  personas no hay "Personas".
- En Comprobantes y en Detalle, los `ANULADA` se listan, pero **el total no los
  suma**: `SUMIFS(…,"<>ANULADA")`, con su valor calculado. Las cortesías tampoco son
  venta.
- Un comprobante con dos formas de pago es **una** fila: "Efectivo $10.00 + Tarjeta $5.00".
- Las fechas, como las muestra la pantalla de Comprobantes (mira cómo las convierte).

### Verificación

1. `test/exportar/xlsx_minimo_test.dart`: el zip tiene las partes esperadas; nombres
   de hoja repetidos o de más de 31 caracteres quedan válidos; un texto con `&`, `<`
   y un carácter de control no rompe el XML.
2. `test/exportar/libro_reporte_test.dart` con datos inventados: el total de cada
   hoja es la suma de sus filas; sin inventario no hay hojas de inventario; con 40
   días no hay hojas por día y Resumen lo avisa.
3. Un test que escriba el libro de ejemplo en `build/ejemplo.xlsx`, y
   `tool/validar_xlsx.sh` que haga `unzip -t`, `xmllint --noout` sobre cada parte y
   `qlmanage -t` para sacar la vista previa. Mira la imagen.
4. `flutter analyze`, `flutter build web --release` y `flutter build apk --debug`.
5. En local, con el usuario con sesión iniciada: bajar un mes de una sucursal y
   **comparar tres números contra la pantalla** (ventas del período, unidades del
   plato más vendido, total de un cierre de caja). Si no coinciden, hay un error en el
   libro: la pantalla es la referencia.

**Puerta.** El usuario abre el archivo **en Excel** (y, si puede, en Google Sheets).
Es la prueba que no se pudo hacer en este Mac. Si Excel ofrece "reparar" el archivo,
no está terminado. Pídele además que revise si falta alguna columna.

---

## Fase 3 — Estructura de escritorio en Flutter

Rama: `web/escritorio`. **No empieces sin el estilo elegido** (sección 10).

**Entrega:** en la web, a 1000 px o más y con sesión iniciada, menú lateral fijo,
barra superior clara, pantalla de inicio de sesión partida, pantalla de carga, y cada
módulo con su dirección. Por debajo de 1000 px, y en el celular y Windows, todo igual.

### Cómo se arma (decisión 1 de la sección 3)

```
MaterialApp.router( builder: (context, child) => … )
  Row
  ├─ menú lateral            ← fuera del Navigator
  └─ Expanded
     └─ child                ← el Router con su único Navigator, como hoy
```

Lo que eso obliga a cuidar:

- **El árbol alrededor de `child` no cambia de forma nunca.** En la web, la `Row`
  existe siempre; con sesión cerrada o ventana angosta el lateral mide 0. Si `child`
  cambiara de lugar al cruzar los 1000 px o al iniciar sesión, se reconstruiría el
  router. Envuélvelo además en un `KeyedSubtree` con una `GlobalKey` guardada en el
  `State`. Fuera de la web, el `builder` devuelve exactamente lo de hoy.
- **El contenido recibe un `MediaQuery` con su ancho real** (ventana menos lateral,
  con tope de 1240 o lo que diga la maqueta). `app.dart` ya explica por qué.
- **El lateral está fuera del `Navigator`: no tiene `Overlay`.** Nada de `Tooltip`,
  `PopupMenuButton` ni `DropdownButton` ahí dentro, o revienta. Tampoco existen
  `Navigator.of(context)` ni `GoRouterState.of(context)`: el lateral recibe el
  `GoRouter` por parámetro. Sus diálogos se abren con
  `router.routerDelegate.navigatorKey.currentContext`.
- **El lateral no es un `Scaffold`** (usa `Material`): con otro `Scaffold` encima, los
  avisos (`SnackBar`) saldrían duplicados.
- **Los diálogos solo oscurecen el contenido**, porque viven en el `Navigator`. Un
  observador de rutas le dice al lateral cuándo hay uno abierto, para oscurecerse y
  no recibir clics.

### Pasos

1. `Capacidades`: `static bool get estructuraEscritorio => kIsWeb;`, con el porqué
   (decisión 2).
2. `lib/core/escritorio/escritorio.dart`: las medidas (`anchoMinimo = 1000`,
   `anchoLateral = 248`, `anchoMaximoContenido`) y `EscritorioScope`, un
   `InheritedWidget` con `activo`. `EscritorioScope.activo(context)` devuelve `false`
   si no hay ninguno arriba: es lo que pasa en el celular.
3. `observador_rutas.dart`:

   ```dart
   class ObservadorRutas extends NavigatorObserver {
     final List<Route<dynamic>> _pila = [];
     /// Hay un diálogo, hoja inferior o menú abierto.
     final ValueNotifier<bool> hayModal = ValueNotifier(false);
     /// …y además oscurece el fondo (un desplegable no lo hace).
     final ValueNotifier<bool> fondoOscurecido = ValueNotifier(false);

     Route<dynamic>? get rutaSuperior => _pila.isEmpty ? null : _pila.last;

     void _actualizar() {
       final arriba = rutaSuperior;
       final modal = arriba is PopupRoute;
       final oscuro = modal && (arriba.barrierColor?.a ?? 0) > 0;
       void aplicar() {
         hayModal.value = modal;
         fondoOscurecido.value = oscuro;
       }
       // El Navigator a veces avisa en pleno build: cambiar un ValueNotifier
       // ahí lanza "setState() called during build".
       if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
         SchedulerBinding.instance.addPostFrameCallback((_) => aplicar());
       } else {
         aplicar();
       }
     }
     // didPush agrega; didPop y didRemove quitan; didReplace cambia. Todos
     // terminan en _actualizar().
   }
   ```

   Se registra con `GoRouter(observers: [observador])`.
4. `menu_escritorio.dart`: las opciones por rol y los prefijos que las marcan como
   activas. **No toques `AppDrawer`**: su lista es la del celular. Deja un comentario
   en cada archivo que apunte al otro.

   | Rol | Opciones (ruta) |
   |---|---|
   | admin | Panel `/admin` · Mesas `/mesero/mesas` (también `/mesero/orden`, `/mesero/para-llevar`) · Por cobrar `/cajero/ordenes` (también `/cajero/factura`) · Cocina `/cocina` · Caja `/cajero/caja` · Comprobantes `/cajero/comprobantes` · Adelantos* `/admin/adelantos` · Reportes `/admin/reportes` · Inventario* `/admin/inventario` · Configuración `/admin/configuracion` |
   | cajero | Panel `/cajero` · Caja · Facturación `/cajero/ordenes` · Comprobantes · Adelantos* `/cajero/adelantos` · Tomar pedidos `/mesero/mesas` |
   | mesero | Panel `/mesero` · Mesas · Para llevar `/mesero/para-llevar` |
   | cocinero | Panel `/cocinero` · Órdenes de cocina `/cocina` |
   | superadmin | Panel `/superadmin` |

   \* Solo con el módulo activo. La opción activa es la del prefijo más largo que
   coincida con la ubicación.
5. Módulos activos: un objeto pequeño que, al iniciar sesión, pregunta una vez
   `InventarioRepository.getAlertas(sucursalId).habilitado` y
   `AdelantosRepository.listar(sucursalId).habilitado` (los dos ya devuelven "no
   habilitado" si algo falla). Se limpia al cerrar sesión.
6. Rutas nuevas en `app_router.dart`: `/admin/inventario`, `/admin/adelantos` y
   `/cajero/adelantos`, que toman la sucursal del usuario del `AuthBloc`. Son aditivas:
   los paneles siguen abriendo esas pantallas como hoy.
7. La ubicación actual, también para lo abierto con `context.push`:

   ```dart
   String ubicacionActual(GoRouter router) {
     final config = router.routerDelegate.currentConfiguration;
     if (config.isEmpty) return '';
     final ultimo = config.matches.last;
     final lista = ultimo is ImperativeRouteMatch ? ultimo.matches : config;
     return lista.uri.path;
   }
   ```

   `routerDelegate` es un `ChangeNotifier`: el lateral lo escucha. Verifica los nombres
   contra `~/.pub-cache/hosted/pub.dev/go_router-14.8.1/lib/src/match.dart`.
8. `lateral.dart`, con el aspecto aprobado. Al tocar una opción:

   ```dart
   void _ir(String ruta) {
     if (observador.hayModal.value) return;
     final arriba = observador.rutaSuperior;
     if (arriba != null && arriba.popDisposition == RoutePopDisposition.doNotPop) {
       // La pantalla tiene cambios sin guardar (la receta): que pregunte ella.
       router.routerDelegate.navigatorKey.currentState?.maybePop();
       return;
     }
     router.go(ruta);
   }
   ```

   Pie del lateral: usuario y rol, "Preferencias" (tamaño del texto con
   `AjustesTexto`; para quien cobra, las dos opciones de `AjustesCobro`) y "Cerrar
   sesión" con su confirmación. Son diálogos propios de escritorio; el `AppDrawer` no
   se toca. Con el texto en "Muy grande", las etiquetas se cortan con puntos
   suspensivos, no se desbordan.
9. `tema_escritorio.dart`: parte de `AppTheme.lightTheme` y cambia lo necesario según
   el estilo elegido. `AppBar` claro, sin elevación, título a la izquierda y borde
   inferior; **`tabBarTheme` con texto oscuro** (el del celular es blanco y sobre la
   barra clara no se vería); transiciones de página sin animación. Guárdalo en un
   `static final`.
10. `app.dart`: arma la `Row` (árbol fijo), el `MediaQuery` del contenido, el `Theme`,
    el `EscritorioScope` y el oscurecimiento del lateral. El lateral se muestra con:
    web, ancho ≥ 1000, sesión iniciada y ubicación distinta de `/login`.
11. **Recargar la página con sesión.** Hoy, al recargar en `/#/admin`, la pantalla se
    construye antes de que termine `AuthCheckRequested`, sin usuario, y el panel
    muestra ceros hasta 30 segundos. Solo en la web: mientras no llegue el primer
    estado que no sea `AuthInitial` ni `AuthLoading`, `WasiApp` muestra una pantalla
    de carga y **no crea el router**. Solo ese primer chequeo: `AuthLoading` también
    se emite al pulsar "Ingresar", y ahí no debe pasar nada.
12. **Filtro por rol** en el `redirect`, solo con `kIsWeb`: admin, todo menos
    `/superadmin`; cajero, `/cajero` y `/mesero`; mesero, `/mesero`; cocinero,
    `/cocinero` y `/cocina`; superadmin, todo. Lo no permitido va al inicio del rol.
    Antes, busca todos los `context.go(` y `context.push(` y confirma que ningún flujo
    de hoy lleva a un rol a una ruta que el filtro cortaría. Va en un commit aparte.
13. Los cuatro paneles: `drawer:` en `null` cuando `EscritorioScope.activo(context)`.
14. Revisa los `AppBar` de la sección 2 bajo el tema claro. Donde haya blanco escrito
    a mano, usa el color del tema (`Theme.of(context).appBarTheme.foregroundColor`):
    en el celular sigue siendo blanco.
15. `login_screen.dart`: disposición partida en web a 900 px o más, reutilizando el
    mismo formulario (`_buildForm`, `_buildLoginButton`).
16. `web/index.html`: pantalla de carga con el logo sobre `#FBE9D6`, que se quita al
    llegar el evento `flutter-first-frame`.
17. Si el usuario eligió Poppins: los `.ttf` (400, 500, 600 y 700) van en
    `web/fonts/` —**no** en `pubspec.yaml`, que cambiaría también el celular— y se
    cargan al arrancar en la web con `FontLoader('Poppins')`. Bajar las fuentes es
    una descarga: pídele permiso. Revisa después que nada se desborde, porque Poppins
    es más ancha que Roboto.
18. Pruebas: `rutaPermitida` por rol, la opción activa por prefijo, y el observador.
19. Sección nueva en el `CLAUDE.md`, "Web de escritorio": por qué no hay `ShellRoute`,
    qué no puede usarse en el lateral y el árbol fijo.

### Lista de comprobación (en local, con el usuario con sesión iniciada)

- Cruzar los 1000 px con un diálogo abierto y un campo a medio escribir: no se pierde nada.
- Iniciar y cerrar sesión: el lateral aparece y desaparece sin parpadeos.
- El menú de cada rol; escribir a mano una ruta ajena al rol.
- Diálogo, hoja inferior y selector de fecha: el lateral se oscurece y no responde.
  Un desplegable: no se oscurece.
- Abrir el cobro de una orden y cancelar. **No cobrar: es producción.**
- Receta con cambios sin guardar y un clic en el lateral: pregunta antes de salir.
- Recargar en `/#/admin/reportes`: sigue ahí, con datos y sin ceros.
- Atrás y adelante del navegador.
- Texto en "Muy grande".
- Ventana de menos de 1000 px: idéntica a la de hoy.
- El usuario prueba el APK en su teléfono: menú, tamaño del texto, cerrar sesión, un
  pedido completo en el restaurante de prueba.

**Puerta.** El usuario la revisa en local antes de cualquier merge. Dile sin vueltas
que **Windows no se probó** y que sigue con la interfaz de siempre.

---

## Fase 4 — Panel y pantallas pensadas para la PC (esbozo)

Se detalla cuando la fase 3 esté en uso. La regla es una sola: la versión ancha va
detrás de `EscritorioScope.activo(context)`, en un widget aparte, y el del celular no
se toca. Cada pantalla es una tarea propia, con su rama.

1. **Panel del administrador:** indicadores, ventas de 7 días (seis llamadas a
   `resumen-diario` hechas una sola vez, más el día de hoy que ya se refresca cada 30
   segundos), órdenes en curso, alertas de inventario y más vendidos
   (`resumen-periodo` de hoy). Las barras, con un widget propio; un paquete de
   gráficos solo si el usuario lo pide.
2. Reportes y Resumen del período en dos columnas.
3. Inventario y Comprobantes como tablas con buscador y filtros.
4. Menú y precios como tabla.
5. Mesas con la orden al lado.

## Fase 5 — Carta digital (después)

Pendiente, sin planificar: subir fotos de platos desde la app (el servicio ya tiene
`POST /api/fotos`), varios diseños de carta, quién la administra (hoy solo el
superadmin, con una clave única) y el IVA mixto. Repo `WasiCarta`.

---

## 10. Registro

Quien ejecuta una fase la marca aquí y anota lo que el siguiente necesita saber.

- [ ] Fase 0 — caché. Hecha en la rama `web/cache-despliegue`, sin commit; falta el OK
  para llevarla a `main`. Probada en local (2026-11-12) con la imagen real: todo sale
  con `no-cache` (y 304 al repetir), `index.html`, `version.json` y el service worker
  con `no-store`, `/salud` responde, y el navegador pide `main.dart.js?v=…` con 200 y
  llega a la pantalla de inicio de sesión sin errores.
- [x] Fase 1 — maqueta. `docs/maqueta-web/index.html`. *Estilo elegido:* **A · Café**
  (2026-11-12) · *Tipografía:* **Roboto**, la que ya se ve hoy: en la fase 3 se salta
  el paso 17 (no se carga Poppins) · *Correcciones:* ninguna.
- [x] Fase 2 — Excel. Código en la rama `web/excel` (2026-11-12). El usuario lo abrió
  en Excel: abre bien y le gustó. Botón en
  Resumen del período e Inventario (solo web, solo ADMIN y SUPER_ADMIN). 17 pruebas en
  `test/exportar/` pasan; `tool/validar_xlsx.sh` da zip íntegro, XML bien formado en
  las 25 partes y vista previa correcta; `flutter analyze` sigue en 124 `info`; web y
  APK compilan. Detalles que la guía no decía: Cierres sale en dos hojas (Cierres y
  Movimientos); los turnos que cruzan la medianoche se cuentan una vez; Proveedores se
  piden una sola vez (son del restaurante); desde Inventario, compras de los últimos
  30 días. *¿Comparado contra la pantalla con datos reales?:* sí (2026-11-12, "Sistema",
  1–12 nov): ventas $1,230.80, 42 comprobantes, ticket $29.21, por mesa $29.92, por
  persona $13.20, ganancia $907.94 y Cafe 17 u / $51.00 / 1 regalado, igual que la
  pantalla. Además cuadran entre hojas: Ventas por día y Cierres suman $1,230.80. El
  archivo real pasó `tool/validar_xlsx.sh`. *¿Abrió bien en Excel?:* —
- [ ] Fase 3 — estructura de escritorio.
- [ ] Fase 4 — panel y pantallas.

**Notas y descubrimientos**

- 2026-11-12 — Guía escrita. Nada de código cambiado todavía.
- 2026-11-12 — Revisada contra el código: confirmados los campos de go_router 14.8.1
  (`RouteMatchList.matches` y `.uri`, `ImperativeRouteMatch.matches`) y el texto exacto
  `"mainJsPath":"main.dart.js"` del `flutter_bootstrap.js` publicado. Se corrigió el
  conteo de diálogos: el riesgo de un `Navigator` anidado era menor de lo que decía la
  primera versión, aunque la decisión 1 se mantiene.
