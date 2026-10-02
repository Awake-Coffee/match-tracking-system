import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await supabase.restore();
    repository = supabase;
  } else {
    repository = DemoLadderRepository();
  }

  final prefs = await SharedPreferences.getInstance();
  runApp(AwakeApp(repository: repository, preferences: prefs));
}
