import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/network/api_client.dart';
import '../data/configuracion_repository.dart';

class UsuariosConfigScreen extends StatefulWidget {
  final String sucursalId;
  const UsuariosConfigScreen({super.key, required this.sucursalId});

  @override
  State<UsuariosConfigScreen> createState() => _UsuariosConfigScreenState();
}

class _UsuariosConfigScreenState extends State<UsuariosConfigScreen> {
  final _repo = ConfiguracionRepository();
  List<UsuarioListModel> _usuarios = [];
  List<RolModel> _roles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() { _loading = true; _error = null; });
      final results = await Future.wait([
        _repo.getUsuarios(widget.sucursalId),
        _repo.getRoles(),
      ]);
      setState(() {
        _usuarios = results[0] as List<UsuarioListModel>;
        _roles    = (results[1] as List<RolModel>)
            .where((r) => !r.nombre.contains('SUPER') && !r.nombre.contains('ADMINISTRADOR'))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Usuarios del personal')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _roles.isEmpty ? null : _showCrearDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
      ],
    ),
  );

  Widget _buildBody() {
    if (_usuarios.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: 64, color: AppColors.info.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('Sin personal configurado',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Crea los usuarios para cajero, mesero y cocinero',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_roles.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _showCrearDialog,
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Crear usuario'),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _usuarios.length,
        itemBuilder: (_, i) => _UsuarioCard(
          usuario: _usuarios[i],
          onToggle: () => _toggle(_usuarios[i]),
        ),
      ),
    );
  }

  Future<void> _toggle(UsuarioListModel u) async {
    try {
      await _repo.toggleUsuario(u.usuarioId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
      );
    }
  }

  void _showCrearDialog() {
    final nombreCtrl    = TextEditingController();
    final usuarioCtrl   = TextEditingController();
    final passwordCtrl  = TextEditingController();
    final correoCtrl    = TextEditingController();
    String? selectedRolId = _roles.isNotEmpty ? _roles.first.rolId : null;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Nuevo usuario', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre completo *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRolId,
                  decoration: const InputDecoration(labelText: 'Rol *'),
                  items: _roles.map((r) => DropdownMenuItem(value: r.rolId, child: Text(r.nombre))).toList(),
                  onChanged: (v) => setDlgState(() => selectedRolId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usuarioCtrl,
                  decoration: const InputDecoration(labelText: 'Usuario (login) *', hintText: 'ej: cajero01'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña *',
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setDlgState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo (opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final nombre   = nombreCtrl.text.trim();
                final usuario  = usuarioCtrl.text.trim();
                final password = passwordCtrl.text;
                if (nombre.isEmpty || usuario.isEmpty || password.isEmpty || selectedRolId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Completa los campos requeridos')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await _repo.crearUsuario(
                    sucursalId: widget.sucursalId,
                    rolId:      selectedRolId!,
                    nombre:     nombre,
                    usuario:    usuario,
                    password:   password,
                    correo:     correoCtrl.text.trim(),
                  );
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Usuario "$usuario" creado'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                  _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsuarioCard extends StatelessWidget {
  final UsuarioListModel usuario;
  final VoidCallback onToggle;
  const _UsuarioCard({required this.usuario, required this.onToggle});

  Color get _rolColor {
    switch (usuario.nombreRol.toUpperCase()) {
      case 'CAJERO':   return AppColors.cajeroColor;
      case 'MESERO':   return AppColors.primary;
      case 'COCINERO': return AppColors.cocineroColor;
      default:         return AppColors.info;
    }
  }

  IconData get _rolIcon {
    switch (usuario.nombreRol.toUpperCase()) {
      case 'CAJERO':   return Icons.point_of_sale_outlined;
      case 'MESERO':   return Icons.room_service_outlined;
      case 'COCINERO': return Icons.kitchen_outlined;
      default:         return Icons.person_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
        border: usuario.activo ? null : Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _rolColor.withOpacity(0.15),
            child: Icon(_rolIcon, color: _rolColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(usuario.nombre,
                    style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                Row(
                  children: [
                    Text('@${usuario.usuario}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _rolColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(usuario.nombreRol,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: _rolColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: usuario.activo, onChanged: (_) => onToggle(), activeColor: AppColors.success),
        ],
      ),
    );
  }
}
