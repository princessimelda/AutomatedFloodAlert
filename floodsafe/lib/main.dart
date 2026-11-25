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
      final api = ApiRepository(
        baseUrl: url,
        accessToken: () => account == null
            ? null
            : Supabase.instance.client.auth.currentSession?.accessToken,
      );
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
                  'FloodSafe could not start. Please try again later.',
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
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: Colors.white)
          .copyWith(
            primary: navy,
            secondary: blue,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: ink,
          ),
      scaffoldBackgroundColor: paper,
      fontFamily: 'Georgia',
      fontFamilyFallback: const ['Lora', 'serif'],
      textTheme: TextTheme(
        displayLarge: titleStyle(52),
        displayMedium: titleStyle(42),
        displaySmall: titleStyle(34),
        headlineLarge: titleStyle(32),
        headlineMedium: titleStyle(28),
        headlineSmall: titleStyle(24),
        titleLarge: titleStyle(22),
        titleMedium: titleStyle(18),
        titleSmall: titleStyle(16),
        bodyMedium: const TextStyle(color: ink, fontSize: 16, height: 1.55),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
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
          textStyle: const TextStyle(
            fontFamily: 'Georgia',
            fontFamilyFallback: ['Lora', 'serif'],
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: blue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
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
