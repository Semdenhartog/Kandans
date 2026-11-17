import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Luistert naar in- en uitloggen.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Huidige gebruiker (null als niet ingelogd).
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

/// Roept een edge function aan met een tijdslimiet: zonder verbinding of bij een hangende server
/// blijft de app anders eindeloos wachten. Bij overschrijding komt een [TimeoutException].
Future<FunctionResponse> invokeFunction(
  SupabaseClient db,
  String name, {
  Map<String, dynamic>? body,
  Duration timeout = const Duration(seconds: 45),
}) =>
    db.functions.invoke(name, body: body).timeout(timeout);

/// Vertaalt technische foutmeldingen naar begrijpelijk Nederlands.
String friendlyError(Object error) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login')) return 'E-mailadres of wachtwoord klopt niet.';
    if (msg.contains('not confirmed')) {
      return 'Je e-mailadres is nog niet bevestigd. Vul eerst je activatiecode in.';
    }
    if (msg.contains('already registered') || msg.contains('already been registered')) {
      return 'Er bestaat al een account met dit e-mailadres.';
    }
    if (msg.contains('expired') || (msg.contains('invalid') && msg.contains('token'))) {
      return 'De code is ongeldig of verlopen. Vraag een nieuwe code aan.';
    }
    if (msg.contains('password')) return 'Kies een sterker wachtwoord (minimaal 8 tekens).';
    if (msg.contains('rate limit')) return 'Te veel pogingen. Wacht even en probeer het opnieuw.';
    return error.message;
  }
  if (error is PostgrestException) {
    return 'Opslaan of ophalen is mislukt (${error.code ?? 'onbekend'}). Probeer het opnieuw.';
  }
  if (error is TimeoutException) {
    return 'Dit duurt te lang. Controleer je verbinding en probeer het opnieuw.';
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'Geen internetverbinding. Controleer je verbinding en probeer het opnieuw.';
  }
  return text.replaceFirst('Exception: ', '');
}
