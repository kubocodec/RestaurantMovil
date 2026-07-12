import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/config_models.dart';
import '../../../core/models/user_model.dart';
import '../../../core/network/api_client.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_event.dart';
import '../../../features/auth/bloc/auth_state.dart';
import '../../../features/configuracion/data/configuracion_repository.dart';
import '../../../features/configuracion/presentation/configuracion_screen.dart';

const _purple      = Color(0xFF7B1FA2);
const _purpleDark  = Color(0xFF4A148C);
const _purpleLight = Color(0x1A7B1FA2);

// ─── MAIN SCREEN ─────────────────────────────────────────────────────────────

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  final _repo = ConfiguracionRepository();
  List<TenantModel> _tenants = [];
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
      final tenants = await _repo.getTenants();
      setState(() { _tenants = tenants; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = ApiClient.parseError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final user = state is AuthAuthenticated ? state.user : null;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Super Administrador'),
            actions: [
              IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                onPressed: () => _confirmLogout(context),
                tooltip: 'Cerrar sesión',
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _purple,
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Nuevo cliente', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
            onPressed: () => _showCrearTenantDialog(context),
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(user),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _buildError()
                          : _buildTenantList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(UserModel? user) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_purpleDark, _purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _purpleDark.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bienvenido,', style: TextStyle(color: Colors.white70, fontFamily: 'Poppins', fontSize: 12)),
                Text(
                  user?.nombre ?? 'Super Admin',
                  style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Control total del sistema',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Poppins')),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 32),
          ),
        ],
      ),
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

  Widget _buildTenantList() {
    if (_tenants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_outlined, size: 64, color: Color(0x407B1FA2)),
            const SizedBox(height: 16),
            const Text('Sin clientes registrados',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _purple),
              icon: const Icon(Icons.add_business_rounded, color: Colors.white),
              label: const Text('Crear primer cliente',
                  style: TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              onPressed: () => _showCrearTenantDialog(context),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Clientes (${_tenants.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              itemCount: _tenants.length,
              itemBuilder: (_, i) => _TenantCard(
                tenant: _tenants[i],
                repo:   _repo,
                onTenantUpdated: _load,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCrearTenantDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CrearTenantDialog(
        repo: _repo,
        onCreated: _load,
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas salir?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }
}

// ─── DIALOG: CREAR TENANT ─────────────────────────────────────────────────────

class _CrearTenantDialog extends StatefulWidget {
  final ConfiguracionRepository repo;
  final VoidCallback onCreated;
  const _CrearTenantDialog({required this.repo, required this.onCreated});

  @override
  State<_CrearTenantDialog> createState() => _CrearTenantDialogState();
}

class _CrearTenantDialogState extends State<_CrearTenantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre  = TextEditingController();
  final _email   = TextEditingController();
  final _ruc     = TextEditingController();
  final _telefono = TextEditingController();
  String _plan   = 'BASIC';
  bool _saving   = false;

  @override
  void dispose() {
    _nombre.dispose(); _email.dispose(); _ruc.dispose(); _telefono.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repo.crearTenant(
        nombre:   _nombre.text.trim(),
        email:    _email.text.trim(),
        ruc:      _ruc.text.trim(),
        telefono: _telefono.text.trim(),
        plan:     _plan,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo cliente', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_nombre, 'Nombre del negocio *', required: true),
                const SizedBox(height: 12),
                _field(_email, 'Email *', required: true, keyboard: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _field(_ruc, 'RUC', keyboard: TextInputType.number),
                const SizedBox(height: 12),
                _field(_telefono, 'Teléfono', keyboard: TextInputType.phone),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _plan,
                  decoration: _inputDecoration('Plan'),
                  items: const [
                    DropdownMenuItem(value: 'BASIC',        child: Text('Basic')),
                    DropdownMenuItem(value: 'PROFESSIONAL', child: Text('Professional')),
                    DropdownMenuItem(value: 'ENTERPRISE',   child: Text('Enterprise')),
                  ],
                  onChanged: (v) => setState(() => _plan = v ?? 'BASIC'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _purple),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Crear', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  TextFormField _field(TextEditingController ctrl, String label, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: _inputDecoration(label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null : null,
    );
  }
}

// ─── TARJETA DE TENANT ───────────────────────────────────────────────────────

class _TenantCard extends StatefulWidget {
  final TenantModel tenant;
  final ConfiguracionRepository repo;
  final VoidCallback onTenantUpdated;
  const _TenantCard({required this.tenant, required this.repo, required this.onTenantUpdated});

  @override
  State<_TenantCard> createState() => _TenantCardState();
}

class _TenantCardState extends State<_TenantCard> {
  List<RestaurantModel> _restaurants = [];
  bool _loading  = false;
  bool _expanded = false;

  Future<void> _loadRestaurants() async {
    setState(() => _loading = true);
    try {
      final r = await widget.repo.getRestaurantsByTenant(widget.tenant.tenantId);
      setState(() { _restaurants = r; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 6, offset: Offset(0, 2))],
        border: widget.tenant.activo ? null : Border.all(color: AppColors.error.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded && _restaurants.isEmpty) _loadRestaurants();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: _purpleLight, shape: BoxShape.circle),
                    child: const Icon(Icons.business_rounded, color: _purple, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.tenant.nombre,
                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('RUC: ${widget.tenant.ruc}  •  ${widget.tenant.plan ?? 'BASIC'}',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  _StatusBadge(activo: widget.tenant.activo),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            // "Añadir restaurant" button always visible when expanded
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _purple,
                    side: const BorderSide(color: _purple),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Añadir restaurante', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
                  onPressed: () => _showCrearRestaurantDialog(context),
                ),
              ),
            ),
            _loading
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : _buildRestaurants(),
          ],
        ],
      ),
    );
  }

  Widget _buildRestaurants() {
    if (_restaurants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Text('Sin restaurantes aún', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: _restaurants.map((r) => _RestaurantRow(
        restaurant: r,
        tenantId:   widget.tenant.tenantId,
        repo:       widget.repo,
        onRestaurantUpdated: _loadRestaurants,
      )).toList(),
    );
  }

  void _showCrearRestaurantDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CrearRestaurantDialog(
        tenantId:  widget.tenant.tenantId,
        repo:      widget.repo,
        onCreated: _loadRestaurants,
      ),
    );
  }
}

// ─── DIALOG: CREAR RESTAURANT ─────────────────────────────────────────────────

class _CrearRestaurantDialog extends StatefulWidget {
  final String tenantId;
  final ConfiguracionRepository repo;
  final VoidCallback onCreated;
  const _CrearRestaurantDialog({required this.tenantId, required this.repo, required this.onCreated});

  @override
  State<_CrearRestaurantDialog> createState() => _CrearRestaurantDialogState();
}

class _CrearRestaurantDialogState extends State<_CrearRestaurantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre  = TextEditingController();
  bool _saving   = false;

  @override
  void dispose() { _nombre.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repo.crearRestaurant(
        tenantId: widget.tenantId,
        nombre:   _nombre.text.trim(),
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo restaurante', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nombre,
          autofocus: true,
          decoration: _inputDecoration('Nombre del restaurante *'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _purple),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Crear', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ─── FILA DE RESTAURANTE ─────────────────────────────────────────────────────

class _RestaurantRow extends StatefulWidget {
  final RestaurantModel restaurant;
  final String tenantId;
  final ConfiguracionRepository repo;
  final VoidCallback onRestaurantUpdated;
  const _RestaurantRow({
    required this.restaurant,
    required this.tenantId,
    required this.repo,
    required this.onRestaurantUpdated,
  });

  @override
  State<_RestaurantRow> createState() => _RestaurantRowState();
}

class _RestaurantRowState extends State<_RestaurantRow> {
  List<SucursalModel> _sucursales = [];
  bool _loading  = false;
  bool _expanded = false;

  Future<void> _loadSucursales() async {
    setState(() => _loading = true);
    try {
      final s = await widget.repo.getSucursalesByRestaurant(widget.restaurant.restaurantId);
      setState(() { _sucursales = s; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded && _sucursales.isEmpty) _loadSucursales();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.restaurant_rounded, size: 18, color: AppColors.earth2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.restaurant.nombre,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                ),
                Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 6),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.earth2,
                  side: BorderSide(color: AppColors.earth2.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Añadir sucursal', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12)),
                onPressed: () => _showCrearSucursalDialog(context),
              ),
            ),
          ),
          _loading
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : _buildSucursales(),
        ],
        const Divider(height: 1, indent: 20, color: Color(0x12000000)),
      ],
    );
  }

  Widget _buildSucursales() {
    if (_sucursales.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(36, 4, 16, 12),
        child: Text('Sin sucursales aún', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: _sucursales.map((s) => _SucursalConfigRow(
        sucursal:     s,
        restaurantId: widget.restaurant.restaurantId,
        tenantId:     widget.tenantId,
      )).toList(),
    );
  }

  void _showCrearSucursalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CrearSucursalDialog(
        restaurantId: widget.restaurant.restaurantId,
        repo:         widget.repo,
        onCreated:    _loadSucursales,
      ),
    );
  }
}

// ─── DIALOG: CREAR SUCURSAL ───────────────────────────────────────────────────

class _CrearSucursalDialog extends StatefulWidget {
  final String restaurantId;
  final ConfiguracionRepository repo;
  final VoidCallback onCreated;
  const _CrearSucursalDialog({required this.restaurantId, required this.repo, required this.onCreated});

  @override
  State<_CrearSucursalDialog> createState() => _CrearSucursalDialogState();
}

class _CrearSucursalDialogState extends State<_CrearSucursalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombre    = TextEditingController();
  final _direccion = TextEditingController();
  final _ciudad    = TextEditingController();
  final _telefono  = TextEditingController();
  final _codigo    = TextEditingController();
  bool _saving     = false;

  @override
  void dispose() {
    _nombre.dispose(); _direccion.dispose(); _ciudad.dispose();
    _telefono.dispose(); _codigo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repo.crearSucursal(
        restaurantId:          widget.restaurantId,
        nombre:                _nombre.text.trim(),
        direccion:             _direccion.text.trim(),
        ciudad:                _ciudad.text.trim(),
        telefono:              _telefono.text.trim(),
        codigoEstablecimiento: _codigo.text.trim(),
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.parseError(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva sucursal', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_nombre,    'Nombre de la sucursal *', required: true),
                const SizedBox(height: 12),
                _field(_direccion, 'Dirección *', required: true),
                const SizedBox(height: 12),
                _field(_ciudad,    'Ciudad'),
                const SizedBox(height: 12),
                _field(_telefono,  'Teléfono', keyboard: TextInputType.phone),
                const SizedBox(height: 12),
                _field(_codigo,    'Código establecimiento (ej: 001)', keyboard: TextInputType.number),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _purple),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Crear', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  TextFormField _field(TextEditingController ctrl, String label, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: _inputDecoration(label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null : null,
    );
  }
}

// ─── FILA DE SUCURSAL ────────────────────────────────────────────────────────

class _SucursalConfigRow extends StatelessWidget {
  final SucursalModel sucursal;
  final String restaurantId;
  final String tenantId;

  const _SucursalConfigRow({
    required this.sucursal,
    required this.restaurantId,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 4, 12, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConfiguracionScreen(
                overrideSucursalId:   sucursal.sucursalId,
                overrideRestaurantId: restaurantId,
                overrideTenantId:     tenantId,
                sucursalNombre:       sucursal.nombre,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.store_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sucursal.nombre,
                          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.primary)),
                      Text(sucursal.direccion,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: AppColors.textSecondary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_outlined, size: 12, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text('Configurar', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── BADGE DE ESTADO ─────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool activo;
  const _StatusBadge({required this.activo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: activo ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
          color: activo ? AppColors.success : AppColors.error,
        ),
      ),
    );
  }
}

// ─── HELPER ──────────────────────────────────────────────────────────────────

InputDecoration _inputDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontFamily: 'Poppins'),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  isDense: true,
);
