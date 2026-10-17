import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import 'auth_widgets.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_firstName, _email, _password, _password2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'Ga akkoord met de privacyverklaring om verder te gaan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      final res = await ref.read(supabaseProvider).auth.signUp(
        email: email,
        password: _password.text,
        data: {
          'first_name': _firstName.text.trim(),
          'full_name': _firstName.text.trim(),
        },
      );
      if (!mounted) return;
      if (res.session == null) {
        // E-mailbevestiging staat aan: eerst de code invullen.
        context.go('/verify?email=${Uri.encodeComponent(email)}');
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: 'Start met RunWise',
      title: 'Jouw beste loopmoment begint hier.',
      subtitle: 'Maak een gratis account. We vragen alleen wat nodig is.',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                decoration: const InputDecoration(labelText: 'Voornaam'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Vul je voornaam in' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-mailadres'),
                validator: (v) {
                  final s = (v ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                      ? null
                      : 'Vul een geldig e-mailadres in';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Wachtwoord',
                  helperText: 'Minimaal 8 tekens',
                ),
                validator: (v) => (v ?? '').length < 8 ? 'Gebruik minimaal 8 tekens' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Herhaal wachtwoord'),
                validator: (v) => v != _password.text ? 'De wachtwoorden zijn niet gelijk' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(color: RwColors.muted, height: 1.4),
                          children: [
                            const TextSpan(text: 'Ik ga akkoord met de '),
                            TextSpan(
                              text: 'privacyverklaring',
                              style: const TextStyle(
                                color: RwColors.accent,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => launchUrl(
                                      Uri.parse(AppConfig.privacyUrl),
                                      mode: LaunchMode.externalApplication,
                                    ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FormError(_error),
              BusyButton(label: 'Account aanmaken', busy: _busy, onPressed: _submit),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Ik heb al een account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
