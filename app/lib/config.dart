/// Build-time configuration, passed with `--dart-define`.
///
/// When either value is missing the app runs in demo mode with an in-memory
/// ladder, so the app can be tried without a backend.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's publishable key (`sb_publishable_...`) or legacy anon key.
  /// Both are safe to ship to browsers; RLS protects the data.
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
