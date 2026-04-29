import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/idle_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Cargar .env (fallback para desarrollo)
  await dotenv.load(fileName: '.env');

  // 2. Cargar configuración persistente (SharedPreferences)
  await AppConfig.init();

  // Kiosk mode: fullscreen, sin status bar ni navigation bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Orientación portrait para el kiosk vertical
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const VMFSApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VMFSApp extends StatelessWidget {
  const VMFSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VMFS USA',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF007ACC),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007ACC),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      // Si la app está configurada → pantalla idle con anuncios.
      // Si es primera instalación → Setup Wizard.
      home: Builder(builder: (context) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          child: AppConfig.isConfigured
              ? const IdleScreen()
              : const SetupWizardScreen(),
        );
      }),
    );
  }
}

