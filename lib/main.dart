import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/idle_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/app_config.dart';
import 'services/accessibility_settings.dart';
import 'services/update_checker.dart';
import 'widgets/accessibility_fab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env is optional — the file is gitignored and may be absent on CI
  // builds or fresh clones. When it isn't present, AppConfig falls back
  // to the production constants baked into app_config.dart, so the app
  // still launches with valid credentials.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env on disk — proceed with baked defaults.
  }
  await AppConfig.init();

  // Quietly poll vms-cloud for new APK releases. The idle screen shows a
  // discreet badge when one is ready.
  UpdateChecker.instance.startBackgroundChecks();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const VMFSApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class VMFSApp extends StatefulWidget {
  const VMFSApp({super.key});

  @override
  State<VMFSApp> createState() => _VMFSAppState();
}

class _VMFSAppState extends State<VMFSApp> {
  final _a11y = AccessibilitySettings.instance;

  @override
  void initState() {
    super.initState();
    _a11y.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _a11y.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VMFS USA',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      // Tema cambia dinámicamente según la configuración de accesibilidad
      theme: _a11y.buildTheme(),
      // builder: inyecta el FAB ♿ en TODAS las pantallas + aplica text scale
      builder: (context, child) {
        final scale = _a11y.textScale;
        final mq    = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: Stack(
            children: [
              child!,
              const AccessibilityFAB(),
            ],
          ),
        );
      },
      home: AppConfig.isConfigured
          ? const IdleScreen()
          : const SetupWizardScreen(),
    );
  }
}
