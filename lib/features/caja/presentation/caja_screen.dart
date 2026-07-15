import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/caja_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../shared/widgets/cierre_detalle_sheet.dart';
import '../data/caja_repository.dart';

class CajaScreen extends StatefulWidget {
  const CajaScreen({super.key});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  final _repo = CajaRepository();
  final _fmt  = NumberFormat('#,##0.00', 'es');
  CajaModel? _caja;
  AperturaCajaModel? _apertura;
  ResumenCajaModel? _resumen;
  bool _loading = true;
  bool _sinCaja = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCaja());
  }

  String get _sucursalId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.sucursalId : '';
  }

  Future<void> _loadCaja() async {
    setState(() { _loading = true; _error = null; _sinCaja = false; });
    try {
      final sid = _sucursalId;
      if (sid.isEmpty) throw Exception('Sin sucursal asignada');
      final cajas = await _repo.getCajasBySucursal(sid);
      if (cajas.isEmpty) {
        if (mounted) setState(() { _loading = false; _sinCaja = true; });
        return;
      }
      final caja = cajas.first;
      final apertura = await _repo.getAperturaActiva(caja.cajaId);
      ResumenCajaModel? resumen;
      if (apertura != null && apertura.isAbierta) {
        try {
          resumen = await _repo.getResumen(apertura.aperturaCierreCajaId);
        } catch (_) {
          resumen = null;
        }
      }
      if (mounted) {
        setState(() {
          _caja = caja;
          _apertura = apertura;
          _resumen = resumen;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = ApiClient.parseError(e); _loading = false; });
    }
  }

  Future<void> _abrirCaja() async {
    if (_caja == null) {
      await _loadCaja();
      if (_caja == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se encontró caja para esta sucursal. Contacta al administrador.'),
            backgroundColor: AppColors.warning,
          ));
        }
        return;
      }
    }
    final caja = _caja;
    if (caja == null || !mounted) return;
    final ctrl = TextEditingController(text: '50.00');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingresa el monto inicial:', style: TextStyle(fontFamily: 'Poppins')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto inicial', prefixText: '\$ '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.abrirCaja(
        cajaId: caja.cajaId,
        montoInicial: double.tryParse(ctrl.text) ?? 50.0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja abierta correctamente'), backgroundColor: AppColors.success),
        );
        _loadCaja();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _cerrarCaja() async {
    final apertura = _apertura;
    if (apertura == null) return;
    final resumen = _resumen;
    final montoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cuenta solo el EFECTIVO del cajón e ingresa el total. El sistema calculará el arqueo (esperado vs. contado).',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            if (resumen != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ventas del turno: \$${_fmt.format(resumen.totalVentas)} '
                '(\$${_fmt.format(resumen.totalVentasEfectivo)} en efectivo, '
                '\$${_fmt.format(resumen.totalVentas - resumen.totalVentasEfectivo)} en otros métodos)',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: montoCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: '\$ '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: obsCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final montoFinal = double.tryParse(montoCtrl.text.replaceAll(',', '.'));
    if (montoFinal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa el efectivo contado para cerrar la caja'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    try {
      final cierre = await _repo.cerrarCaja(
        aperturaCierreCajaId: apertura.aperturaCierreCajaId,
        montoFinal: montoFinal,
        observaciones: obsCtrl.text.trim().isEmpty ? 'Cierre de turno' : obsCtrl.text.trim(),
      );
      if (mounted) {
        await mostrarCierreDetalle(context, cierre);
        _loadCaja();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _registrarMovimiento(String tipo) async {
    final apertura = _apertura;
    if (apertura == null) return;
    final conceptoCtrl = TextEditingController();
    final montoCtrl    = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'INGRESO' ? 'Registrar ingreso' : 'Registrar egreso'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixText: '\$ '),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: conceptoCtrl,
              decoration: const InputDecoration(labelText: 'Concepto'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _repo.registrarMovimiento(
                  aperturaCierreCajaId: apertura.aperturaCierreCajaId,
                  tipo: tipo,
                  monto: double.tryParse(montoCtrl.text) ?? 0.0,
                  concepto: conceptoCtrl.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Movimiento registrado'), backgroundColor: AppColors.success),
                  );
                  _loadCaja();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gestión de Caja'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCaja)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildError()
              : _sinCaja
                  ? _buildSinCaja()
                  : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadCaja,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildStatusCard(),
              const SizedBox(height: 20),
              if (_apertura?.isAbierta == true) ...[
                _buildActions(),
                const SizedBox(height: 20),
                _buildVentasPorPlato(),
                const SizedBox(height: 20),
                _buildMovimientos(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final apertura = _apertura;
    final caja = _caja;
    final isAbierta = apertura?.isAbierta == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isAbierta
              ? [AppColors.cajeroColor, const Color(0xFF1B5E20)]
              : [AppColors.textSecondary, const Color(0xFF424242)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isAbierta ? AppColors.cajeroColor : AppColors.textSecondary).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(isAbierta ? Icons.lock_open_rounded : Icons.lock_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAbierta ? 'Caja ABIERTA' : 'Caja CERRADA',
                      style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    if (apertura != null)
                      Text(
                        'Desde: ${DateFormat('HH:mm', 'es').format(apertura.fechaApertura)}',
                        style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12),
                      ),
                    if (caja != null)
                      Text(caja.nombre, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (apertura != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CajaStatItem(label: 'Inicial', value: '\$${_fmt.format(apertura.montoInicial)}'),
                if (_resumen != null) ...[
                  _CajaStatItem(label: 'Ventas', value: '\$${_fmt.format(_resumen!.totalVentas)}'),
                  _CajaStatItem(label: 'Ingresos', value: '\$${_fmt.format(_resumen!.totalIngresos)}'),
                  _CajaStatItem(label: 'Egresos', value: '-\$${_fmt.format(_resumen!.totalEgresos)}'),
                ],
              ],
            ),
            if (_resumen != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Debe haber en caja (efectivo)',
                          style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 13)),
                        Text('\$${_fmt.format(_resumen!.montoEsperado)}',
                          style: const TextStyle(
                            color: Colors.white, fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700, fontSize: 18)),
                      ],
                    ),
                    if (_resumen!.totalVentas - _resumen!.totalVentasEfectivo > 0.009) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Efectivo: \$${_fmt.format(_resumen!.totalVentasEfectivo)} · '
                          'Tarjeta/Transf.: \$${_fmt.format(_resumen!.totalVentas - _resumen!.totalVentasEfectivo)}',
                          style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isAbierta ? _cerrarCaja : _abrirCaja,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: isAbierta ? AppColors.error : AppColors.cajeroColor,
              ),
              child: Text(
                isAbierta ? 'Cerrar caja' : 'Abrir caja',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(child: _ActionBtn(icon: Icons.add_circle_outline, label: 'Ingreso', color: AppColors.success, onTap: () => _registrarMovimiento('INGRESO'))),
        const SizedBox(width: 12),
        Expanded(child: _ActionBtn(icon: Icons.remove_circle_outline, label: 'Egreso', color: AppColors.error, onTap: () => _registrarMovimiento('EGRESO'))),
      ],
    );
  }

  Widget _buildVentasPorPlato() {
    final ventas = _resumen?.ventasPorPlato ?? [];
    if (ventas.isEmpty) return const SizedBox.shrink();
    final totalPlatos = ventas.fold(0, (s, v) => s + v.cantidad);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ventas por plato',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                Text('$totalPlatos platos',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...ventas.map((v) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${v.cantidad}',
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                      fontSize: 13, color: AppColors.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(v.plato,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Text('\$${_fmt.format(v.total)}',
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMovimientos() {
    final movimientos = _resumen?.movimientos ?? [];
    if (movimientos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textHint),
              SizedBox(height: 8),
              Text('Sin movimientos registrados',
                style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Movimientos del turno (${movimientos.length})',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const Divider(height: 1),
          ...movimientos.map((m) => ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (m.esIngreso ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                m.esIngreso ? Icons.add_circle_outline : Icons.remove_circle_outline,
                color: m.esIngreso ? AppColors.success : AppColors.error,
                size: 18,
              ),
            ),
            title: Text(m.concepto,
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              '${m.usuario} · ${DateFormat('HH:mm', 'es').format(m.fecha.toLocal())}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
            trailing: Text(
              '${m.esIngreso ? '+' : '-'}\$${_fmt.format(m.monto)}',
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
                color: m.esIngreso ? AppColors.success : AppColors.error)),
          )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSinCaja() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.point_of_sale_outlined, size: 72, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text('Sin caja asignada',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Text('No hay ninguna caja configurada para esta sucursal.\nContacta al administrador.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCaja,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Poppins')),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _loadCaja, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _CajaStatItem extends StatelessWidget {
  final String label;
  final String value;
  const _CajaStatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 11)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
