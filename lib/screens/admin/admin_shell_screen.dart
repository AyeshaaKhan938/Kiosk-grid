import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'admin_hardware_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_local_ads_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_products_screen.dart';
import '../../services/admin_api_service.dart';
import '../../services/local_kiosk_store.dart';
import '../../services/offline_sync_service.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin/admin_page_scaffold.dart';

/// Admin panel shell with bottom navigation.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  late int _index;

  static const _screens = [
    AdminDashboardScreen(),
    AdminInventoryScreen(),
    AdminOrdersScreen(),
    AdminProductsScreen(),
    AdminLocalAdsScreen(),
    AdminHardwareScreen(),
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard_rounded),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2_rounded),
      label: 'Inventory',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Orders',
    ),
    NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront_rounded),
      label: 'Products',
    ),
    NavigationDestination(
      icon: Icon(Icons.campaign_outlined),
      selectedIcon: Icon(Icons.campaign_rounded),
      label: 'Ads',
    ),
    NavigationDestination(
      icon: Icon(Icons.precision_manufacturing_outlined),
      selectedIcon: Icon(Icons.precision_manufacturing_rounded),
      label: 'Hardware',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab.clamp(0, 5);
    _ensureLocalSnapshot();
  }

  Future<void> _ensureLocalSnapshot() async {
    if (!LocalKioskStore.instance.hasSnapshot) {
      await LocalKioskStore.instance.seedEmptyIfNeeded();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = OfflineSyncService.instance.isOnline;
    final pending = LocalKioskStore.instance.pendingMutationCount;

    if (!AdminApiService.canUseLocalAdmin) {
      return AdminTheme.withLightTheme(
        child: Scaffold(
          backgroundColor: AdminColors.canvas,
          appBar: AdminShellAppBar(
            title: 'Admin panel',
            onBack: () => Navigator.of(context).pop(),
          ),
          body: _NoTokenView(onConfigure: () => Navigator.of(context).pop()),
        ),
      );
    }

    return AdminTheme.withLightTheme(
      child: Scaffold(
        backgroundColor: AdminColors.canvas,
        appBar: AdminShellAppBar(
          title: _titles[_index],
          onBack: () => Navigator.of(context).pop(),
          actions: [
            if (!online)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          pending > 0 ? 'Offline · $pending' : 'Offline',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: AdminBottomChrome(
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: _destinations,
          ),
        ),
      ),
    );
  }

  static const _titles = [
    'Dashboard',
    'Inventory',
    'Orders',
    'Products',
    'Ads',
    'Hardware',
  ];
}

class _NoTokenView extends StatelessWidget {
  const _NoTokenView({required this.onConfigure});
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: AdminSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AdminColors.danger.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.key_off_rounded,
                  size: 40,
                  color: AdminColors.danger,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Admin not available',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AdminColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect to vms-cloud once to download catalog data, or set a '
                'management API token in Settings.',
                style: TextStyle(
                  color: AdminColors.textSecondary,
                  height: 1.5,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onConfigure,
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Go to Settings'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(220, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
