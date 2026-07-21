import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/models/factura_model.dart';
import '../../core/network/api_client.dart';
import '../../features/facturacion/data/facturacion_repository.dart';

/// Estado de la factura electrónica en el SRI, con acciones según el caso:
/// ver el RIDE (PDF) cuando está autorizada, actualizar cuando está en
/// proceso y reintentar cuando falló. Si el comprobante no fue enviado al
/// SRI (restaurante sin facturación electrónica) no muestra nada.
class SriEstadoPanel extends StatefulWidget {
  final FacturaModel factura;

  /// Tras el cobro la emisión ocurre en segundo plano: con esto el panel
  /// consulta el estado automáticamente unos segundos después.
  final bool autoConsultar;

  /// Notifica la factura actualizada (p. ej. para que la impresión del
  /// ticket ya incluya la clave de acceso).
  final ValueChanged<FacturaModel>? onActualizada;

  const SriEstadoPanel({
    super.key,
    required this.factura,
    this.autoConsultar = false,
    this.onActualizada,
  });

  @override
  State<SriEstadoPanel> createState() => _SriEstadoPanelState();
}

class _SriEstadoPanelState extends State<SriEstadoPanel> {
  final _repo = FacturacionRepository();
  late FacturaModel _factura = widget.factura;
  bool _cargando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoConsultar) {
      // La emisión corre en el backend justo después del cobro: se da un
      // margen antes de preguntar cómo terminó.
      _timer = Timer(const Duration(seconds: 3), _consultarSilencioso);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Consulta sin molestar: si el comprobante no se envió al SRI (SRI
  /// desactivado para el restaurante) simplemente no se muestra el panel.
  Future<void> _consultarSilencioso() async {
    try {
      final f = await _repo.getFactura(_factura.facturaVentaId);
      if (!mounted) return;
      setState(() => _factura = f);
      widget.onActualizada?.call(f);
      // Si quedó en proceso, un segundo intento sincroniza contra el SRI.
      if (f.sriEstado == 'PROCESANDO') {
        _timer = Timer(const Duration(seconds: 3), _actualizarEstado);
      }
    } catch (_) {
      // silencioso: el cobro ya está hecho, esto es solo informativo
    }
  }

  Future<void> _actualizarEstado() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final f = await _repo.getEstadoSri(_factura.facturaVentaId);
      if (!mounted) return;
      setState(() => _factura = f);
      widget.onActualizada?.call(f);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reintentar() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final f = await _repo.emitirSri(_factura.facturaVentaId);
      if (!mounted) return;
      setState(() => _factura = f);
      widget.onActualizada?.call(f);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Factura enviada al SRI'), backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verPdf() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final pdf = await _repo.getPdfSri(_factura.facturaVentaId);
      final url = pdf.url ?? pdf.previewUrl;
      if (url == null || url.isEmpty) {
        throw Exception('El PDF aún no está disponible');
      }
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('No se pudo abrir el navegador');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _factura;
    if (!f.tieneSri) return const SizedBox.shrink();

    final (color, icono, titulo) = switch (f.sriEstado) {
      'AUTORIZADA'  => (AppColors.success, Icons.verified_outlined, 'Factura electrónica autorizada (SRI)'),
      'PROCESANDO'  => (AppColors.warning, Icons.hourglass_top_rounded, 'Factura electrónica en proceso (SRI)'),
      'RECHAZADA'   => (AppColors.error, Icons.cancel_outlined, 'Factura rechazada por el SRI'),
      _             => (AppColors.error, Icons.error_outline, 'Error al enviar la factura al SRI'),
    };
    final fallo = f.sriEstado == 'RECHAZADA' || f.sriEstado == 'ERROR';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(titulo,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12.5,
                      fontWeight: FontWeight.w700, color: color)),
              ),
              if (_cargando)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (f.sriClaveAcceso?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text('Clave de acceso:\n${f.sriClaveAcceso}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.3)),
          ],
          if (fallo && (f.sriMensaje?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 6),
            Text(f.sriMensaje!,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: color)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (f.sriAutorizada)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cargando ? null : _verPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Ver PDF',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                ),
              if (f.sriEstado == 'PROCESANDO')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cargando ? null : _actualizarEstado,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Actualizar estado',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                ),
              if (fallo)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cargando ? null : _reintentar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Reintentar envío',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
