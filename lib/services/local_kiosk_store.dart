import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/advertisement.dart';
import '../models/machine_slot.dart';
import 'app_config.dart';

/// On-device catalog, inventory, products, and ads for offline operation.
class LocalKioskStore {
  LocalKioskStore._();

  static final LocalKioskStore instance = LocalKioskStore._();

  static const _fileName = 'local_kiosk_data.json';

  Map<String, dynamic>? _slotsCatalogJson;
  List<Map<String, dynamic>> _adminSlots = [];
  Map<String, dynamic>? _productsPage;
  Map<String, dynamic>? _advertisementsJson;
  List<Map<String, dynamic>> _pendingMutations = [];
  DateTime? _updatedAt;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool get hasSnapshot =>
      _loaded &&
      (_slotsCatalogJson != null ||
          _adminSlots.isNotEmpty ||
          _productsPage != null ||
          (_advertisementsJson != null &&
              _advertisementsJson!.isNotEmpty));

  int get pendingMutationCount => _pendingMutations.length;

  DateTime? get updatedAt => _updatedAt;

  Future<void> init() async {
    if (_loaded || kIsWeb) {
      _loaded = true;
      return;
    }
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _applyLoaded(raw);
      }
    } catch (e) {
      debugPrint('[local_store] load failed: $e');
    }
    _loaded = true;
  }

  Future<void> saveSlotsCatalog(Map<String, dynamic> json) async {
    _slotsCatalogJson = Map<String, dynamic>.from(json);
    _touch();
    await _persist();
  }

  Future<void> saveAdminSlots(Map<String, dynamic> data) async {
    _adminSlots = (data['slots'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _touch();
    await _persist();
  }

  Future<void> saveProductsPage(Map<String, dynamic> data) async {
    _productsPage = Map<String, dynamic>.from(data);
    _touch();
    await _persist();
  }

  Future<void> saveAdvertisements(Map<String, dynamic> json) async {
    _advertisementsJson = Map<String, dynamic>.from(json);
    _touch();
    await _persist();
  }

  Future<void> saveAdvertisementsResponse(AdvertisementsResponse ads) async {
    await saveAdvertisements(ads.toJson());
  }

  /// Empty catalog for first-time offline provisioning.
  Future<void> seedEmptyIfNeeded({int slotCount = 30}) async {
    if (hasSnapshot) return;

    final catalogSlots = <Map<String, dynamic>>[];
    final adminSlots = <Map<String, dynamic>>[];
    for (var i = 1; i <= slotCount; i++) {
      catalogSlots.add({
        'line_number': i,
        'product_id': null,
        'product_name': 'Empty slot',
        'product_image': null,
        'price': 0.0,
        'current_stock': 0,
        'max_stock': 10,
        'is_available': false,
        'is_fault': false,
      });
      adminSlots.add({
        'id': -i,
        'line_number': i,
        'product_id': null,
        'product_name': 'Empty slot',
        'product_image': null,
        'price': '0.00',
        'current_stock': 0,
        'max_stock': 10,
        'is_available': false,
        'is_fault': false,
      });
    }

    _slotsCatalogJson = {
      'machine_number': AppConfig.machineNo,
      'machine_name': 'Kiosk ${AppConfig.machineNo}',
      'slots': catalogSlots,
      'categories': <Map<String, dynamic>>[],
    };
    _adminSlots = adminSlots;
    _productsPage = {
      'data': <Map<String, dynamic>>[],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
    };
    _advertisementsJson = AdvertisementsResponse.empty.toJson();
    _touch();
    await _persist();
  }

  MachineSlotsResponse? loadSlotsCatalog() {
    final raw = _slotsCatalogJson;
    if (raw == null) return null;
    try {
      return MachineSlotsResponse.fromJson(raw);
    } catch (e) {
      debugPrint('[local_store] slots parse failed: $e');
      return null;
    }
  }

  Map<String, dynamic> loadAdminSlots() => {'slots': _cloneList(_adminSlots)};

  Map<String, dynamic> loadProductsPage() =>
      _productsPage != null
          ? Map<String, dynamic>.from(_productsPage!)
          : {
              'data': <Map<String, dynamic>>[],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
            };

  Future<void> saveAdvertisementSlot(
    AdSlot slot,
    List<Advertisement> ads,
  ) async {
    final current = loadAdvertisements();
    final updated = AdvertisementsResponse(
      groupId: current.groupId ?? -1,
      groupName: current.groupName ?? 'Local ads',
      screensaver: slot == AdSlot.screensaver
          ? ads
          : current.screensaver,
      top: slot == AdSlot.top ? ads : current.top,
      externalScreen: slot == AdSlot.externalScreen
          ? ads
          : current.externalScreen,
    );
    await saveAdvertisementsResponse(updated);
  }

  Future<void> upsertLocalAd(AdSlot slot, Advertisement ad) async {
    final current = loadAdvertisements();
    List<Advertisement> list;
    switch (slot) {
      case AdSlot.screensaver:
        list = List<Advertisement>.from(current.screensaver);
      case AdSlot.top:
        list = List<Advertisement>.from(current.top);
      case AdSlot.externalScreen:
        list = List<Advertisement>.from(current.externalScreen);
    }

    final idx = list.indexWhere((a) => a.id == ad.id);
    if (idx >= 0) {
      list[idx] = ad;
    } else {
      list.add(ad);
    }
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await saveAdvertisementSlot(slot, list);
  }

  Future<void> removeLocalAd(AdSlot slot, int adId) async {
    final current = loadAdvertisements();
    List<Advertisement> list;
    switch (slot) {
      case AdSlot.screensaver:
        list = current.screensaver.where((a) => a.id != adId).toList();
      case AdSlot.top:
        list = current.top.where((a) => a.id != adId).toList();
      case AdSlot.externalScreen:
        list =
            current.externalScreen.where((a) => a.id != adId).toList();
    }
    await saveAdvertisementSlot(slot, list);
  }

  int nextLocalAdId() =>
      -DateTime.now().millisecondsSinceEpoch.remainder(1000000000);

  AdvertisementsResponse loadAdvertisements() {
    final raw = _advertisementsJson;
    if (raw == null) return AdvertisementsResponse.empty;
    try {
      return AdvertisementsResponse.fromJson(raw);
    } catch (_) {
      return AdvertisementsResponse.empty;
    }
  }

  Future<void> applySlotPatch(int slotId, Map<String, dynamic> fields) async {
    for (final slot in _adminSlots) {
      if ((slot['id'] as num?)?.toInt() == slotId) {
        slot.addAll(fields);
        break;
      }
    }
    _syncCatalogSlotFromAdmin(slotId);
    _touch();
    await _persist();
  }

  Future<void> applyProductCreate(Map<String, dynamic> product) async {
    _productsPage ??= {
      'data': <Map<String, dynamic>>[],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
    };
    final list = (_productsPage!['data'] as List?) ?? <dynamic>[];
    final products = list.cast<Map<String, dynamic>>().toList();
    final localId = product['id'] as int? ??
        -DateTime.now().millisecondsSinceEpoch.remainder(1000000000);
    final copy = Map<String, dynamic>.from(product)..['id'] = localId;
    products.add(copy);
    _productsPage!['data'] = products;
    final meta = (_productsPage!['meta'] as Map<String, dynamic>?) ?? {};
    meta['total'] = products.length;
    _productsPage!['meta'] = meta;
    _touch();
    await _persist();
  }

  Future<void> applyProductUpdate(
    int productId,
    Map<String, dynamic> fields,
  ) async {
    final products =
        (_productsPage?['data'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    for (final p in products) {
      if ((p['id'] as num?)?.toInt() == productId) {
        p.addAll(fields);
        break;
      }
    }
    _productsPage ??= {'data': products};
    _productsPage!['data'] = products;
    _touch();
    await _persist();
  }

  Future<void> enqueueMutation(Map<String, dynamic> mutation) async {
    _pendingMutations.add({
      ...mutation,
      'id': mutation['id'] ??
          'm-${DateTime.now().millisecondsSinceEpoch}-${_pendingMutations.length}',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _persist();
  }

  Future<void> removeMutation(String id) async {
    _pendingMutations.removeWhere((m) => m['id'] == id);
    await _persist();
  }

  List<Map<String, dynamic>> pendingMutations() =>
      _pendingMutations.map((e) => Map<String, dynamic>.from(e)).toList();

  void _syncCatalogSlotFromAdmin(int slotId) {
    final catalog = _slotsCatalogJson;
    if (catalog == null) return;
    Map<String, dynamic>? admin;
    for (final s in _adminSlots) {
      if ((s['id'] as num?)?.toInt() == slotId) {
        admin = s;
        break;
      }
    }
    if (admin == null) return;

    final line = (admin['line_number'] as num?)?.toInt();
    final slots = catalog['slots'];
    if (slots is! List || line == null) return;

    for (final raw in slots) {
      if (raw is! Map) continue;
      if ((raw['line_number'] as num?)?.toInt() == line) {
        raw['product_name'] = admin['product_name'] ?? raw['product_name'];
        raw['price'] = admin['price'] ?? raw['price'];
        raw['current_stock'] = admin['current_stock'] ?? raw['current_stock'];
        raw['max_stock'] = admin['max_stock'] ?? raw['max_stock'];
        raw['is_available'] = admin['is_available'] ?? raw['is_available'];
        raw['is_fault'] = admin['is_fault'] ?? raw['is_fault'];
        raw['product_image'] = admin['product_image'] ?? raw['product_image'];
        break;
      }
    }
  }

  void _applyLoaded(Map<String, dynamic> raw) {
    if (raw['machine_no']?.toString() != AppConfig.machineNo) {
      return;
    }
    _slotsCatalogJson = raw['slots_catalog'] as Map<String, dynamic>?;
    _adminSlots = (raw['admin_slots'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _productsPage = raw['products_page'] as Map<String, dynamic>?;
    _advertisementsJson = raw['advertisements'] as Map<String, dynamic>?;
    _pendingMutations = (raw['pending_mutations'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ts = raw['updated_at']?.toString();
    _updatedAt = ts != null ? DateTime.tryParse(ts) : null;
  }

  Future<void> _persist() async {
    if (kIsWeb) return;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final payload = {
        'machine_no': AppConfig.machineNo,
        'updated_at': _updatedAt?.toIso8601String(),
        'slots_catalog': _slotsCatalogJson,
        'admin_slots': _adminSlots,
        'products_page': _productsPage,
        'advertisements': _advertisementsJson,
        'pending_mutations': _pendingMutations,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('[local_store] persist failed: $e');
    }
  }

  void _touch() => _updatedAt = DateTime.now();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  List<Map<String, dynamic>> _cloneList(List<Map<String, dynamic>> src) =>
      src.map((e) => Map<String, dynamic>.from(e)).toList();
}
