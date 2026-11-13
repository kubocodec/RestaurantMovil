import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Una columna de [TablaEscritorio].
class ColumnaTabla {
  final String titulo;
  final int flex;
  /// Números y montos van a la derecha, para que se lean en columna.
  final bool derecha;
  /// Ancho fijo en vez de flex (íconos de acción).
  final double? ancho;

  const ColumnaTabla(this.titulo, {this.flex = 2, this.derecha = false, this.ancho});
}

/// Una fila: sus celdas (en el orden de las columnas) y qué pasa al tocarla.
class FilaTabla {
  final List<Widget> celdas;
  final VoidCallback? onTap;
  /// Fila atenuada: un comprobante anulado, un insumo desactivado.
  final bool apagada;

  const FilaTabla(this.celdas, {this.onTap, this.apagada = false});
}

/// Tabla de la web de escritorio: encabezado fijo y filas que se desplazan.
///
/// Es una lista con columnas por flex y no un DataTable: con miles de filas
/// (los comprobantes de un día de evento) DataTable las arma todas de una
/// vez, y además no reparte el ancho como el resto de la pantalla.
class TablaEscritorio extends StatelessWidget {
  final List<ColumnaTabla> columnas;
  final List<FilaTabla> filas;
  final Widget? vacio;
  final EdgeInsets padding;

  const TablaEscritorio({
    super.key,
    required this.columnas,
    required this.filas,
    this.vacio,
    this.padding = const EdgeInsets.fromLTRB(28, 8, 28, 28),
  });

  static const estiloCelda = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary);
  static const estiloSecundario = TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary);
  static const _estiloCabecera = TextStyle(
      fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: AppColors.textHint);

  /// Texto de una línea, cortado con puntos suspensivos si no entra.
  static Widget texto(String t, {TextStyle? estilo, bool negrita = false}) => Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (estilo ?? estiloCelda).copyWith(fontWeight: negrita ? FontWeight.w600 : null),
      );

  /// Monto o número alineado en columna.
  static Widget numero(String t, {Color? color, bool negrita = false}) => Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: estiloCelda.copyWith(
          color: color,
          fontWeight: negrita ? FontWeight.w700 : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  /// Estado en una píldora de color.
  static Widget pildora(String t, Color color) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
          child: Text(t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
      );

  Widget _fila(List<Widget> celdas) => Row(
        children: [
          for (var i = 0; i < columnas.length; i++)
            if (columnas[i].ancho != null)
              SizedBox(width: columnas[i].ancho, child: i < celdas.length ? celdas[i] : null)
            else
              Expanded(
                flex: columnas[i].flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: columnas[i].derecha ? Alignment.centerRight : Alignment.centerLeft,
                    child: i < celdas.length ? celdas[i] : const SizedBox.shrink(),
                  ),
                ),
              ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceVariant))),
                child: _fila([for (final c in columnas) Text(c.titulo.toUpperCase(), maxLines: 1, style: _estiloCabecera)]),
              ),
              Expanded(
                child: filas.isEmpty
                    ? Center(child: vacio ?? const Text('Sin datos', style: estiloSecundario))
                    : ListView.builder(
                        itemCount: filas.length,
                        itemBuilder: (_, i) {
                          final f = filas[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: f.onTap,
                              child: Opacity(
                                opacity: f.apagada ? 0.55 : 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: const BoxDecoration(
                                      border: Border(bottom: BorderSide(color: AppColors.surface))),
                                  child: _fila(f.celdas),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
