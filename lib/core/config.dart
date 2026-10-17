/// Instellingen die bij het bouwen worden meegegeven.
///
/// Start de app met:
///   flutter run --dart-define-from-file=config.json
///
/// config.json (staat NIET in git, zie config.example.json):
///   {
///     "SUPABASE_URL": "https://jouw-project.supabase.co",
///     "SUPABASE_ANON_KEY": "sb_publishable_..."
///   }
///
/// Gebruik hier alleen de publieke anon/publishable key, nooit de service-role key.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Link naar de privacyverklaring (Play Store vereist er een).
  static const privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://runwise.netlify.app/privacy.html',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Standaardlocatie als er geen GPS of route is (Barneveld).
  static const fallbackLatitude = 52.1404;
  static const fallbackLongitude = 5.5847;
}
