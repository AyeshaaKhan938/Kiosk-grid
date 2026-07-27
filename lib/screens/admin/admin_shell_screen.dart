import 'package:flutter/material.dart';
import 'admin_dashboard_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_products_screen.dart';
import '../../services/admin_api_service.dart';

/// Shell del panel admin con barra de navegación inferior.
/// Accesible desde AdminConfigScreen tras autenticación con PIN.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  static const _screens = [
    AdminDashboardScreen(),
    AdminInventoryScreen(),
    AdminOrdersScreen(),
    AdminProductsScreen(),
  ];

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded),       label: 'Dashboard'),
    BottomNavigationBarItem(icon: Icon(Icons.inventory_2_rounded),     label: 'Inventory'),
    BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded),    label: 'Orders'),
    BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded),      label: 'Products'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final bg  = Theme.of(context).scaffoldBackgroundColor;

    // ── Guard: token not configured ─────────────────────────────────────────
    if (!AdminApiService.hasToken) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text(
            'Admin Panel',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
        ),
        body: _NoTokenView(onConfigure: () => Navigator.of(context).pop()),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: Text(
          _titles[_index],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.admin_panel_settings_rounded,
                color: cs.onPrimary.withValues(alpha: 0.7)),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex:    _index,
        onTap:           (i) => setState(() => _index = i),
        type:            BottomNavigationBarType.fixed,
        backgroundColor: cs.surface,
        selectedItemColor:   cs.primary,
        unselectedItemColor: cs.onSurface.withValues(alpha: 0.5),
        selectedLabelStyle:  const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        items: _items,
      ),
    );
  }

  static const _titles = ['Dashboard', 'Inventory', 'Orders', 'Products'];
}

// ── No-token placeholder ─────────────────────────────────────────────────────

class _NoTokenView extends StatelessWidget {
  const _NoTokenView({required this.onConfigure});
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final tt  = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.key_off_rounded,
                  size: 56, color: cs.error),
            ),
            const SizedBox(height: 24),
            Text(
              'API Token Not Configured',
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'A management API token is required to access the Admin Panel.\n\n'
              'Go back to Settings → Lottery & API Token and enter your token.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.65),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Go to Settings'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 48),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
