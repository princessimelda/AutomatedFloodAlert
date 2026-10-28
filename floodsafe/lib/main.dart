import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'ui.dart';
import 'account/account_screen.dart';
import 'home.dart';
import 'dashboard/dashboard_data.dart';
import 'location/location_service.dart';
import 'data/api_repository.dart';
import 'data/content_repository.dart';
import 'assistant/assistant_repository.dart';
import 'account/account_repository.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AccountRepository? account;
  const projectUrl = String.fromEnvironment('FLOODSAFE_SUPABASE_URL');
  const publishableKey = String.fromEnvironment(
    'FLOODSAFE_SUPABASE_PUBLISHABLE_KEY',
  );
  if (projectUrl.isNotEmpty && publishableKey.isNotEmpty) {
    try {
      final uri = Uri.parse(projectUrl);
      if (uri.scheme != 'https' ||
          !uri.hasAuthority ||
          !publishableKey.startsWith('sb_publishable_')) {
        throw ArgumentError('Invalid public account configuration');
      }
      await Supabase.initialize(
        url: projectUrl,
        publishableKey: publishableKey,
      );
      account = SupabaseAccountRepository(
        Supabase.instance.client,
        confirmationRedirectUrl: kIsWeb ? Uri.base.origin : null,
      );
    } catch (_) {
      // Public Home remains usable when account startup is unavailable.
    }
  }
  const url = String.fromEnvironment('FLOODSAFE_API_URL');
  if (url.isEmpty) {
    runApp(FloodSafeApp(accountRepository: account));
  } else {
    try {
      final api = ApiRepository(baseUrl: url);
      runApp(
        FloodSafeApp(
          repository: api,
          contentRepository: api,
          assistantRepository: api,
          connectedToApi: true,
          accountRepository: account,
        ),
      );
    } on ArgumentError {
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Text(
                  'Invalid API configuration. Use HTTPS, or localhost for development.',
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}

class FloodSafeApp extends StatelessWidget {
  const FloodSafeApp({
    super.key,
    this.repository,
    this.locationService,
    this.contentRepository,
    this.assistantRepository,
    this.accountRepository,
    this.connectedToApi = false,
  });
  final DashboardRepository? repository;
  final LocationService? locationService;
  final ContentRepository? contentRepository;
  final AssistantRepository? assistantRepository;
  final AccountRepository? accountRepository;
  final bool connectedToApi;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FloodSafe · Nairobi',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: Colors.white),
      scaffoldBackgroundColor: paper,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 15, height: 1.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    home: HomeScreen(
      repository: repository,
      locationService: locationService,
      contentRepository: contentRepository,
      assistantRepository: assistantRepository,
      accountRepository: accountRepository,
      connectedToApi: connectedToApi,
    ),
    routes: {
      '/home': (_) => HomeScreen(
        repository: repository,
        locationService: locationService,
        contentRepository: contentRepository,
        assistantRepository: assistantRepository,
        accountRepository: accountRepository,
        connectedToApi: connectedToApi,
      ),
      '/sign-in': (_) => AccountScreen(repository: accountRepository),
    },
  );
}
