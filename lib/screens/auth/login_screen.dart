import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/error_banner.dart';

/// Screen 2a: email + password login.
///
/// Navigation on success is handled by the router redirect watching auth
/// state, not by this screen pushing a route. That keeps one source of truth
/// for "where should a signed-in user be" and means a session restored on
/// cold start lands in the same place as a fresh login.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text,
          password: _passwordController.text,
        );
    // Success navigates via the router redirect; failure lands in the
    // controller state and renders in the banner below.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              // Keeps the form readable on tablets and landscape rather than
              // stretching inputs the full width of the screen.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(theme: theme),
                    const SizedBox(height: 36),

                    ErrorBanner(error: state.error),

                    TextFormField(
                      controller: _emailController,
                      enabled: !isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: Validators.email,
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      enabled: !isLoading,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: Validators.loginPassword,
                      onFieldSubmitted: (_) => isLoading ? null : _submit(),
                    ),
                    const SizedBox(height: 26),

                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text('Log in'),
                    ),
                    const SizedBox(height: 12),

                    OutlinedButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              // Drop any stale error so it does not appear
                              // on the registration form.
                              ref
                                  .read(authControllerProvider.notifier)
                                  .clearError();
                              context.push(Routes.register);
                            },
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.phone_in_talk_rounded,
              size: 34, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          'Welcome back',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Log in to continue to ${AppConstants.appName}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.textTheme.bodySmall?.color),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
