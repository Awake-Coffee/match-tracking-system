import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/demo_repository.dart';
import 'data/ladder_repository.dart';
import 'data/supabase_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  final LadderRepository repository;
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    final supabase = SupabaseLadderRepository(Supabase.instance.client);
    // A failed restore must not block runApp, or the HTML splash never goes away.
    await supabase.restore().catchError(
      (Object e) => debugPrint('Session restore failed: $e'),
    );
    repository = supabase;
  } else {
    repository = DemoLadderRepository();
  }

  runApp(AwakeApp(repository: repository));
}
