import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/error_banner.dart';

/// Screen 2b: name, email, password, confirm password.
///
/// As with login, a successful registration navigates through the router
/// redirect rather than an explicit push.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authControllerProvider.notifier).register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: isLoading
              ? null
              : () {
                  ref.read(authControllerProvider.notifier).clearError();
                  context.pop();
                },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Create account', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'A few details and you are ready to call.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.textTheme.bodySmall?.color),
                    ),
                    const SizedBox(height: 30),

                    ErrorBanner(error: state.error),

                    TextFormField(
                      controller: _nameController,
                      enabled: !isLoading,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'How others will see you',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: Validators.name,
                      onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocus,
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
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'At least 6 characters',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: Validators.password,
                      // Revalidates the confirm field live, so a mismatch is
                      // flagged while typing rather than only on submit.
                      onChanged: (_) {
                        if (_confirmController.text.isNotEmpty) {
                          _formKey.currentState?.validate();
                        }
                      },
                      onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirmController,
                      focusNode: _confirmFocus,
                      enabled: !isLoading,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (value) => Validators.confirmPassword(
                          value, _passwordController.text),
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
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 12),

                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              ref
                                  .read(authControllerProvider.notifier)
                                  .clearError();
                              context.pop();
                            },
                      child: const Text('Already have an account? Log in'),
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
