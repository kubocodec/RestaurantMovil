import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/models/factura_model.dart';
import '../../core/network/api_client.dart';
import '../../features/facturacion/data/facturacion_repository.dart';

/// Formulario de cliente para facturar: registra uno nuevo o edita los datos
/// del encontrado (la cédula/RUC identifica al cliente y no se cambia al
/// editar). Devuelve el ClienteModel guardado al cerrar.
///
/// Se usa tanto al cobrar como al emitir después la factura de una nota de
/// venta desde el historial de comprobantes.
class ClienteFormDialog extends StatefulWidget {
  final FacturacionRepository repo;
  final ClienteModel? cliente;   // null = registrar nuevo
  final String? cedulaInicial;   // prellenar cédula al registrar

  const ClienteFormDialog({super.key, required this.repo, this.cliente, this.cedulaInicial});

  @override
  State<ClienteFormDialog> createState() => _ClienteFormDialogState();
}

class _ClienteFormDialogState extends State<ClienteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre    = TextEditingController(text: widget.cliente?.nombre ?? '');
  late final _cedula    = TextEditingController(
      text: widget.cliente?.cedulaRuc ?? widget.cedulaInicial ?? '');
  late final _email     = TextEditingController(text: widget.cliente?.email ?? '');
  late final _telefono  = TextEditingController(text: widget.cliente?.telefono ?? '');
  late final _direccion = TextEditingController(text: widget.cliente?.direccion ?? '');
  bool _saving = false;

  bool get _esEdicion => widget.cliente != null;

  @override
  void dispose() {
    _nombre.dispose(); _cedula.dispose(); _email.dispose();
    _telefono.dispose(); _direccion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final ClienteModel guardado;
      if (_esEdicion) {
        guardado = await widget.repo.actualizarCliente(
          clienteId: widget.cliente!.clienteId,
          nombre:    _nombre.text.trim(),
          email:     _email.text.trim(),
          telefono:  _telefono.text.trim(),
          direccion: _direccion.text.trim(),
        );
      } else {
        guardado = await widget.repo.crearCliente(
          nombre:    _nombre.text.trim(),
          cedulaRuc: _cedula.text.trim(),
          email:     _email.text.trim(),
          telefono:  _telefono.text.trim(),
          direccion: _direccion.text.trim(),
        );
      }
      if (mounted) {
        Navigator.pop(context, guardado);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esEdicion ? 'Cliente actualizado' : 'Cliente registrado'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      // El backend rechaza (422) si la cédula/RUC ya existe en el tenant. En
      // vez de dejar al cajero con un error y el formulario lleno, se busca
      // ese cliente y se le ofrece. Si la búsqueda no lo encuentra, el fallo
      // fue otro (red, validación) y se muestra tal cual.
      if (!_esEdicion) {
        final existente = await widget.repo.buscarClientePorCedula(_cedula.text.trim());
        if (existente != null && mounted) {
          setState(() => _saving = false);
          await _ofrecerExistente(existente);
          return;
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
      ));
    }
  }

  /// La cédula ya está registrada: se muestra de quién es y se ofrece usarlo
  /// tal cual o corregir sus datos (el email es el que recibe la factura).
  Future<void> _ofrecerExistente(ClienteModel existente) async {
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ese cliente ya está registrado',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existente.nombre,
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
            Text('CI/RUC: ${existente.cedulaRuc}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
            Text(
              existente.tieneEmail
                  ? existente.email!
                  : 'Sin email: la factura irá al email de la sucursal',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5,
                color: existente.tieneEmail ? AppColors.textSecondary : AppColors.warning),
            ),
            if (existente.telefono?.isNotEmpty ?? false)
              Text(existente.telefono!,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
            if (existente.direccion?.isNotEmpty ?? false)
              Text(existente.direccion!,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancelar'), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'editar'),
              child: const Text('Editar sus datos')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'usar'),
              child: const Text('Usar este cliente')),
        ],
      ),
    );
    if (!mounted || accion == null || accion == 'cancelar') return;

    if (accion == 'usar') {
      Navigator.pop(context, existente);
      return;
    }
    // Editar: se abre el formulario en modo edición sobre el cliente real; si
    // guarda, ese es el que se devuelve al cobro.
    final actualizado = await showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteFormDialog(repo: widget.repo, cliente: existente),
    );
    if (actualizado != null && mounted) Navigator.pop(context, actualizado);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esEdicion ? 'Editar cliente' : 'Registrar cliente',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombre,
                  autofocus: !_esEdicion,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nombre / Razón social *',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cedula,
                  enabled: !_esEdicion,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cédula / RUC *',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    helperText: _esEdicion ? 'La cédula/RUC no se puede cambiar' : null,
                  ),
                  validator: (v) {
                    final ced = (v ?? '').trim();
                    if (ced.isEmpty) return 'La cédula/RUC es requerida';
                    if (ced.length != 10 && ced.length != 13) {
                      return 'Debe tener 10 (cédula) o 13 (RUC) dígitos';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (recibe la factura electrónica)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    final email = (v ?? '').trim();
                    if (email.isEmpty) return null; // opcional: cae al email de la sucursal
                    if (!email.contains('@') || !email.contains('.')) return 'Email inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _direccion,
                  decoration: const InputDecoration(
                      labelText: 'Dirección', prefixIcon: Icon(Icons.place_outlined)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _guardar,
          child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_esEdicion ? 'Guardar cambios' : 'Registrar'),
        ),
      ],
    );
  }
}
