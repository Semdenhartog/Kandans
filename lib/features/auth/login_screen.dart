import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(
            email: email,
            password: _password.text,
          );
      // De router stuurt automatisch door naar /today.
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('not confirmed') && mounted) {
        context.go('/verify?email=${Uri.encodeComponent(email)}');
        return;
      }
      setState(() => _error = friendlyError(e));
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Vul eerst je e-mailadres in.');
      return;
    }
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(email);
      if (mounted) {
        showMessage(context, 'Als dit adres bij ons bekend is, ontvang je een e-mail om je wachtwoord te herstellen.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: 'Welkom terug',
      title: 'Log in op RunWise.',
      subtitle: 'Loop niet zomaar. Loop op het beste moment.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-mailadres'),
                validator: (v) => (v ?? '').contains('@') ? null : 'Vul een geldig e-mailadres in',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Wachtwoord'),
                validator: (v) => (v ?? '').isEmpty ? 'Vul je wachtwoord in' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: const Text('Wachtwoord vergeten?', style: TextStyle(color: RwColors.muted)),
                ),
              ),
              FormError(_error),
              BusyButton(label: 'Inloggen', busy: _busy, onPressed: _submit),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/signup'),
                child: const Text('Nieuw hier? Account aanmaken'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
