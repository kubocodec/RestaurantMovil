import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/exportar/descarga.dart';
import '../../../core/exportar/xlsx_minimo.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/plataforma/capacidades.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import 'datos_exportacion.dart';
import 'libro_reporte.dart';
import 'recolector.dart';

/// Diálogo "Descargar Excel": se eligen las hojas, se ve el avance mientras
/// se piden los datos y al final el navegador baja el archivo.
///
/// Es un StatefulWidget propio y no un builder suelto, por la trampa del
/// CLAUDE.md: el estado vive aquí y no se destruye mientras el diálogo cierra.
class ExportarExcelDialogo extends StatefulWidget {
  final String restaurantId;
  final List<SucursalExcel> sucursales;
  /// Todas las sucursales del restaurante (el resumen se pide por restaurante).
  final bool todas;
  final String alcance;
  final DateTime desde;
  final DateTime hasta;
  final Set<SeccionExcel> disponibles;
  /// Texto bajo el título; por defecto, el período.
  final String? detalle;

  const ExportarExcelDialogo({
    super.key,
    required this.restaurantId,
    required this.sucursales,
    required this.todas,
    required this.alcance,
    required this.desde,
    required this.hasta,
    required this.disponibles,
    this.detalle,
  });

  /// El botón aparece solo en la web y para administradores: el resumen del
  /// período, los cierres y las compras son endpoints de ADMIN, y un cajero
  /// recibiría un libro lleno de huecos.
  static bool disponible(BuildContext context) {
    if (!Capacidades.descargarArchivos) return false;
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated &&
        (s.user.rol == UserRole.admin || s.user.rol == UserRole.superadmin);
  }

  /// Abre el diálogo. Devuelve el mensaje para mostrar al terminar, o null si
  /// se canceló.
  static Future<String?> mostrar(BuildContext context, ExportarExcelDialogo dialogo) =>
      showDialog<String>(context: context, barrierDismissible: false, builder: (_) => dialogo);

  @override
  State<ExportarExcelDialogo> createState() => _ExportarExcelDialogoState();
}

enum _Fase { eligiendo, trabajando, error }

class _ExportarExcelDialogoState extends State<ExportarExcelDialogo> {
  late final Set<SeccionExcel> _elegidas;
  late final int _dias;
  late final bool _porDiaPermitido;
  final _cancelacion = CancelacionExportacion();

  _Fase _fase = _Fase.eligiendo;
  String _paso = 'Preparando…';
  int _hechas = 0;
  int _total = 0;
  String? _error;

  static const _t13 = TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textPrimary);
  static const _t11 = TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary);

  @override
  void initState() {
    super.initState();
    _dias = RecolectorExcel.diasEntre(widget.desde, widget.hasta).length;
    _porDiaPermitido = RecolectorExcel.detallePorDiaPermitido(_dias, widget.sucursales.length);
    _elegidas = widget.disponibles
        .where((s) => s != SeccionExcel.proveedores && (_porDiaPermitido || !s.esPorDia))
        .toSet();
  }

  String _f(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _descargar() async {
    setState(() {
      _fase = _Fase.trabajando;
      _paso = 'Preparando…';
      _hechas = 0;
      _total = 0;
    });
    try {
      final datos = await RecolectorExcel().recolectar(
        restaurantId: widget.restaurantId,
        sucursales: widget.sucursales,
        todas: widget.todas,
        alcance: widget.alcance,
        desde: widget.desde,
        hasta: widget.hasta,
        secciones: _elegidas,
        cancelacion: _cancelacion,
        progreso: (paso, hechas, total) {
          if (!mounted) return;
          setState(() {
            _paso = paso;
            _hechas = hechas;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _paso = 'Armando el archivo…');
      // Que el texto se dibuje antes del trabajo pesado, que no deja pintar.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final nombre = nombreArchivo(datos);
      final bytes = construirXlsx(armarLibro(datos));
      await descargarArchivo(bytes, nombre, mimeXlsx);
      if (!mounted) return;
      final avisos = datos.notas.length;
      Navigator.of(context).pop(avisos == 0
          ? 'Excel descargado: $nombre'
          : 'Excel descargado con $avisos aviso${avisos == 1 ? '' : 's'}: revisa la hoja Resumen.');
    } on ExportacionCancelada {
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.error;
        _error = ApiClient.parseError(e);
      });
    }
  }

  void _cancelar() {
    if (_fase == _Fase.trabajando) {
      _cancelacion.cancelada = true;
      setState(() => _paso = 'Cancelando…');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Descargar Excel'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.detalle ?? '${widget.alcance} · del ${_f(widget.desde)} al ${_f(widget.hasta)}',
                  style: _t11),
              const SizedBox(height: 12),
              switch (_fase) {
                _Fase.eligiendo => _eleccion(),
                _Fase.trabajando => _avance(),
                _Fase.error => Text('No se pudo armar el Excel: $_error',
                    style: _t13.copyWith(color: AppColors.error)),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _paso == 'Cancelando…' ? null : _cancelar,
          child: Text(_fase == _Fase.error ? 'Cerrar' : 'Cancelar'),
        ),
        if (_fase != _Fase.trabajando)
          ElevatedButton.icon(
            onPressed: _elegidas.isEmpty ? null : _descargar,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_fase == _Fase.error ? 'Reintentar' : 'Descargar'),
          ),
      ],
    );
  }

  Widget _eleccion() {
    final grupos = GrupoExcel.values
        .where((g) => widget.disponibles.any((s) => s.grupo == g))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cada sección marcada sale en su propia hoja.', style: _t11),
        for (final g in grupos) ...[
          const SizedBox(height: 10),
          Text(g.titulo.toUpperCase(),
              style: _t11.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          if (g == GrupoExcel.porDia && !_porDiaPermitido)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'El período tiene $_dias días${widget.sucursales.length > 1 ? ' y ${widget.sucursales.length} sucursales' : ''}: '
                'el detalle día por día se arma hasta ${RecolectorExcel.maxDiasDetalle} días y de a una sucursal. '
                'Elige un período más corto para tenerlo.',
                style: _t11.copyWith(color: AppColors.warning),
              ),
            ),
          Wrap(
            spacing: 4,
            children: [
              for (final s in SeccionExcel.values.where((s) => s.grupo == g && widget.disponibles.contains(s)))
                SizedBox(
                  width: 250,
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    title: Text(s.titulo, style: _t13),
                    value: _elegidas.contains(s),
                    onChanged: (s.esPorDia && !_porDiaPermitido)
                        ? null
                        : (v) => setState(() => v == true ? _elegidas.add(s) : _elegidas.remove(s)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _avance() {
    final fraccion = _total == 0 ? null : _hechas / _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_paso, style: _t13.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraccion,
            minHeight: 8,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(_total == 0 ? 'Empezando…' : '$_hechas de $_total consultas', style: _t11),
        const SizedBox(height: 4),
        const Text('Puedes seguir usando Wasi en otra pestaña. El archivo baja solo al terminar.',
            style: _t11),
      ],
    );
  }
}
