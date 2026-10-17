import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import 'auth_widgets.dart';

/// Activatiecode uit de welkomstmail invullen.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Vul de code uit de e-mail in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.verifyOTP(
            type: OtpType.signup,
            email: widget.email,
            token: code,
          );
      // Ingelogd: de router stuurt door naar /today.
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(supabaseProvider).auth.resend(type: OtpType.signup, email: widget.email);
      if (mounted) showMessage(context, 'Nieuwe code verstuurd naar ${widget.email}.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: 'Nog één stap',
      title: 'Bevestig je e-mailadres.',
      subtitle: 'We hebben een code gestuurd naar ${widget.email}. Vul die hieronder in. '
          'Niets ontvangen? Kijk ook in je spammap.',
      children: [
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(hintText: '123456'),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 16),
        FormError(_error),
        BusyButton(label: 'Activeer account', busy: _busy, onPressed: _verify),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _resend,
          child: const Text('Stuur de code opnieuw', style: TextStyle(color: RwColors.muted)),
        ),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Terug naar inloggen', style: TextStyle(color: RwColors.muted)),
        ),
      ],
    );
  }
}
