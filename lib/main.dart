import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/idle_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/app_config.dart';
import 'services/accessibility_settings.dart';
import 'services/board_heartbeat.dart';
import 'services/kiosk_lockdown.dart';
import 'services/log_file_util.dart';
import 'services/update_checker.dart';
import 'widgets/accessibility_fab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env is optional — the file is gitignored and may be absent on CI
  // builds, web targets, or fresh clones. On web we skip the load entirely
  // because the file isn't bundled there and trying to fetch it just spams
  // a noisy 404 in the console before throwing. Either way we initialize
  // dotenv so later `dotenv.env[...]` reads return null instead of
  // throwing NotInitializedError, and AppConfig falls through to the
  // production constants baked into app_config.dart.
  if (kIsWeb) {
    dotenv.testLoad(fileInput: '');
  } else {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      dotenv.testLoad(fileInput: '');
    }
  }
  await AppConfig.init();

  // First entry in the on-disk log — gives field-debug log files a
  // recognizable "process started" marker.
  LogFileUtil.i('app.start');

  // If the kiosk has never finished its setup wizard, the admin still
  // needs to reach Android Settings to connect Wi-Fi, grant permissions
  // and finish provisioning. Tell the native side to keep Lock Task
  // Mode + immersive + key-blocking OFF until SetupWizardScreen flips
  // it back on at the end of the wizard. Configured installs come up
  // pinned immediately — same as before, no behaviour change.
  if (!AppConfig.isConfigured) {
    await KioskLockdown.setKioskModeAllowed(false);
    LogFileUtil.i('kiosk.lockdown.disabled_for_setup');
  }

  // Quietly poll vms-cloud for new APK releases. The idle screen shows a
  // discreet badge when one is ready.
  UpdateChecker.instance.startBackgroundChecks();

  // Periodic CMD 0xE1 heartbeat against the Reyeah board — surfaces
  // "board went silent / UART cable came loose" faster than waiting
  // for a customer to attempt a vend and see nothing happen. Runs
  // through the same single-flight gate the dispense flow uses, so
  // it queues behind active dispenses instead of fighting on the TTY.
  BoardHeartbeat.instance.start();

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
