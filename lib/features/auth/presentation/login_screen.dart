import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(AuthLoginRequested(
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          // En la web, con lugar, la pantalla se parte en dos (maqueta del
          // 2026-11-12). El formulario es el mismo; en el celular, nada cambia.
          if (kIsWeb && MediaQuery.sizeOf(context).width >= 900) {
            return _buildPartida(isLoading);
          }
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildForm(isLoading),
                    const SizedBox(height: 32),
                    _buildLoginButton(isLoading),
                    const SizedBox(height: 24),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPartida(bool isLoading) {
    const blanco = Colors.white;
    const tenue = Color(0xBFFFFFFF);
    Widget ventaja(IconData icono, String texto) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, size: 19, color: blanco),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(texto, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Color(0xE6FFFFFF))),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 21,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryDark, AppColors.primary, AppColors.earth2],
                stops: [0, 0.7, 1],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.restaurant, size: 28, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 26),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: const Text('Tu restaurante, desde cualquier pantalla',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, color: blanco)),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: const Text(
                      'Pedidos, cobro, inventario y reportes de todas tus sucursales. '
                      'Lo que el mesero anota en el celular lo ves aquí al instante.',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, height: 1.6, color: tenue)),
                ),
                const Spacer(),
                ventaja(Icons.soup_kitchen_outlined, 'Pedidos y cocina en tiempo real'),
                ventaja(Icons.receipt_long_outlined, 'Facturación electrónica con el SRI'),
                ventaja(Icons.table_view_outlined, 'Reportes en Excel para tu contador'),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 20,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      _buildForm(isLoading),
                      const SizedBox(height: 28),
                      _buildLoginButton(isLoading),
                      const SizedBox(height: 24),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.restaurant, size: 48, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          'Wasi',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gestión inteligente para tu negocio',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildForm(bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Iniciar sesión',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ingresa tus credenciales para continuar',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _userCtrl,
            enabled: !isLoading,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu usuario' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            enabled: !isLoading,
            obscureText: _obscurePass,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textHint,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : _submit,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text('Ingresar'),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        '© 2025 Wasi · Todos los derechos reservados',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textHint,
        ),
      ),
    );
  }
}
