import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/services/app_lock_service.dart';
import '../../shared/widgets.dart';
import 'auth_widgets.dart';
import '../../core/i18n.dart';

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
      // Laat de telefoon aanbieden om het wachtwoord te bewaren (Google of Samsung Pass).
      TextInput.finishAutofillContext();
      AppLockService.instance.offerAfterLogin = true;
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
      setState(() => _error = tr('Vul eerst je e-mailadres in.'));
      return;
    }
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(email);
      if (mounted) {
        showMessage(context, tr('Als dit adres bij ons bekend is, ontvang je een e-mail om je wachtwoord te herstellen.'));
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: tr('Welkom terug'),
      title: tr('Log in op Kadans.'),
      subtitle: tr('Loop niet zomaar. Loop op het beste moment.'),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: [AutofillHints.email, AutofillHints.username],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: tr('E-mailadres')),
                validator: (v) => (v ?? '').contains('@') ? null : tr('Vul een geldig e-mailadres in'),
              ),
              SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [AutofillHints.password],
                decoration: InputDecoration(labelText: tr('Wachtwoord')),
                validator: (v) => (v ?? '').isEmpty ? tr('Vul je wachtwoord in') : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: Text(tr('Wachtwoord vergeten?'), style: TextStyle(color: RwColors.muted)),
                ),
              ),
              FormError(_error),
              BusyButton(label: tr('Inloggen'), busy: _busy, onPressed: _submit),
              SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/signup'),
                child: Text(tr('Nieuw hier? Account aanmaken')),
              ),
            ],
          ),
          ),
        ),
      ],
    );
  }
}
