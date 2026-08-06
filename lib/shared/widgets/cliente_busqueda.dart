import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/models/factura_model.dart';
import '../../core/network/api_client.dart';
import '../../features/facturacion/data/facturacion_repository.dart';
import 'cliente_form_dialog.dart';

/// Lo digitado en el buscador solo sirve para prellenar la cédula del
/// formulario si son dígitos; si se buscó por nombre, devuelve null.
String? soloCedula(String texto) {
  final t = texto.trim();
  return RegExp(r'^\d+$').hasMatch(t) ? t : null;
}

/// Busca clientes por nombre, cédula/RUC o email y devuelve el elegido:
/// con un solo resultado lo selecciona directo, con varios los muestra en una
/// lista y sin resultados abre el formulario para registrarlo en el momento.
///
/// Devuelve null si el cajero cancela. Se usa al cobrar y al emitir después
/// la factura de una nota de venta.
Future<ClienteModel?> buscarClienteInteractivo(
  BuildContext context,
  FacturacionRepository repo,
  String consulta,
) async {
  final q = consulta.trim();
  if (q.isEmpty) return null;

  final List<ClienteModel> encontrados;
  try {
    encontrados = await repo.buscarClientes(q);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error,
      ));
    }
    return null;
  }
  if (!context.mounted) return null;

  if (encontrados.length == 1) return encontrados.first;

  if (encontrados.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Cliente no encontrado. Regístralo con el formulario.'),
      backgroundColor: AppColors.warning,
    ));
    return showDialog<ClienteModel>(
      context: context,
      builder: (_) => ClienteFormDialog(repo: repo, cedulaInicial: soloCedula(q)),
    );
  }

  return showDialog<ClienteModel>(
    context: context,
    builder: (_) => _ElegirClienteDialog(clientes: encontrados),
  );
}

/// Lista de coincidencias cuando la búsqueda devuelve más de un cliente
/// (pasa sobre todo al buscar por nombre).
class _ElegirClienteDialog extends StatelessWidget {
  final List<ClienteModel> clientes;

  const _ElegirClienteDialog({required this.clientes});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${clientes.length} clientes encontrados',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: clientes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = clientes[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.nombre,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                'CI/RUC: ${c.cedulaRuc}${c.tieneEmail ? ' · ${c.email}' : ''}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5, color: AppColors.textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}
