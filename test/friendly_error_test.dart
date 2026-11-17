import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/core/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('bekende inlogfouten krijgen een Nederlandse zin', () {
    expect(friendlyError(const AuthException('Invalid login credentials')), contains('klopt niet'));
    expect(friendlyError(const AuthException('Email not confirmed')), contains('bevestigd'));
    expect(friendlyError(const AuthException('User already registered')), contains('bestaat al'));
    expect(friendlyError(const AuthException('Token has expired or is invalid')), contains('verlopen'));
    expect(friendlyError(const AuthException('email rate limit exceeded')), contains('Te veel pogingen'));
  });

  test('databasefout toont de code, niet de ruwe tekst', () {
    final t = friendlyError(const PostgrestException(message: 'secret detail', code: '42501'));
    expect(t, contains('42501'));
    expect(t, isNot(contains('secret detail')));
  });

  test('geen verbinding wordt herkend', () {
    expect(friendlyError(Exception('SocketException: failed host lookup')), contains('internetverbinding'));
  });

  test('overige fouten: tekst zonder "Exception: "', () {
    expect(friendlyError(Exception('Iets anders')), 'Iets anders');
  });
}
