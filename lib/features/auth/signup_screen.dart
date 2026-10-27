import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../profile/privacy_screen.dart';
import 'auth_widgets.dart';
import '../../core/i18n.dart';

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
      setState(() => _error = tr('Ga akkoord met de privacyverklaring om verder te gaan.'));
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
      eyebrow: tr('Start met Kadans'),
      title: tr('Jouw beste loopmoment begint hier.'),
      subtitle: tr('Maak een gratis account. We vragen alleen wat nodig is.'),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _firstName,
                textCapitalization: TextCapitalization.words,
                autofillHints: [AutofillHints.givenName],
                decoration: InputDecoration(labelText: tr('Voornaam')),
                validator: (v) => (v ?? '').trim().isEmpty ? tr('Vul je voornaam in') : null,
              ),
              SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: [AutofillHints.email],
                decoration: InputDecoration(labelText: tr('E-mailadres')),
                validator: (v) {
                  final s = (v ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                      ? null
                      : tr('Vul een geldig e-mailadres in');
                },
              ),
              SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: tr('Wachtwoord'),
                  helperText: tr('Minimaal 8 tekens'),
                ),
                validator: (v) => (v ?? '').length < 8 ? tr('Gebruik minimaal 8 tekens') : null,
              ),
              SizedBox(height: 14),
              TextFormField(
                controller: _password2,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Herhaal wachtwoord')),
                validator: (v) => v != _password.text ? tr('De wachtwoorden zijn niet gelijk') : null,
              ),
              SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(color: RwColors.muted, height: 1.4),
                          children: [
                            TextSpan(text: tr('Ik ga akkoord met de ')),
                            TextSpan(
                              text: tr('privacyverklaring'),
                              style: TextStyle(
                                color: RwColors.accent,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openPrivacy(context),
                            ),
                            TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              FormError(_error),
              BusyButton(label: tr('Account aanmaken'), busy: _busy, onPressed: _submit),
              SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                child: Text(tr('Ik heb al een account')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
