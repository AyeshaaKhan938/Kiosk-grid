import 'app_config.dart';
import 'advertisement_service.dart';
import 'kiosk_device_auth.dart';
import 'offline_sync_service.dart';
import 'slot_service.dart';

/// Refreshes catalog + ads in the background when the device has network.
Future<void> warmCloudCacheIfOnline() async {
  if (!AppConfig.isConfigured || !kioskHasDeviceAuth) {
    return;
  }

  if (!await OfflineSyncService.instance.isCloudReachable()) {
    return;
  }

  try {
    await SlotService.fetchSlots();
  } catch (_) {}

  try {
    await AdvertisementService.fetchAds();
  } catch (_) {}
}
