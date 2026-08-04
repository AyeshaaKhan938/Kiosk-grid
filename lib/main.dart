import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/kiosk_home_screen.dart';
import 'screens/setup_wizard_screen.dart';
import 'services/app_config.dart';
import 'services/lottery_stock_service.dart';
import 'services/accessibility_settings.dart';
import 'services/board_heartbeat.dart';
import 'services/kiosk_lockdown.dart';
import 'services/local_kiosk_store.dart';
import 'services/log_auto_uploader.dart';
import 'services/log_file_util.dart';
import 'services/offline_sync_service.dart';
import 'services/update_checker.dart';
import 'utils/web_reset.dart';
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
  await LocalKioskStore.instance.init();
  await OfflineSyncService.instance.start();

  // Web dev: open /?reset_setup=1 in the browser address bar (full page
  // load — terminal hot restart alone does not pass this query param).
  if (kIsWeb && Uri.base.queryParameters['reset_setup'] == '1') {
    await wipeBrowserStorage();
    await AppConfig.init();
    stripSetupResetQuery();
    LogFileUtil.i('app.reset_setup_via_url configured=${AppConfig.isConfigured}');
  }

  await LotteryStockService.init();

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

  // Periodic CMD 0xE1 heartbeat — slot vending boards only.
  if (!AppConfig.isBketCooler) {
    BoardHeartbeat.instance.start();
  }

  // Auto-ship log files to vms-cloud — first pass 60 s after launch,
  // then every 6 hours. The operator can flip this off via admin →
  // "Auto-upload logs" if logs ever need to stop flowing.
  LogAutoUploader.instance.start();

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
      theme: _a11y.buildTheme().copyWith(
        splashFactory: InkSparkle.splashFactory,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
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
          ? const KioskHomeScreen()
          : const SetupWizardScreen(),
    );
  }
}
