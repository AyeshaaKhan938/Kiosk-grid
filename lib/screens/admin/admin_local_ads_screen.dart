import 'package:flutter/material.dart';

import '../../models/advertisement.dart';
import '../../services/advertisement_service.dart';
import '../../services/local_kiosk_store.dart';
import '../../services/offline_sync_service.dart';
import '../../utils/ad_media.dart';

/// Manage idle-screen and banner ads locally on the kiosk.
class AdminLocalAdsScreen extends StatefulWidget {
  const AdminLocalAdsScreen({super.key});

  @override
  State<AdminLocalAdsScreen> createState() => _AdminLocalAdsScreenState();
}

class _AdminLocalAdsScreenState extends State<AdminLocalAdsScreen> {
  AdSlot _slot = AdSlot.screensaver;
  List<Advertisement> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = LocalKioskStore.instance.loadAdvertisements();
    if (mounted) {
      setState(() {
        _ads = _adsForSlot(data, _slot);
        _loading = false;
      });
    }
  }

  List<Advertisement> _adsForSlot(AdvertisementsResponse data, AdSlot slot) {
    switch (slot) {
      case AdSlot.screensaver:
        return List<Advertisement>.from(data.screensaver);
      case AdSlot.top:
        return List<Advertisement>.from(data.top);
      case AdSlot.externalScreen:
        return List<Advertisement>.from(data.externalScreen);
    }
  }

  Future<void> _openForm({Advertisement? ad}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdFormSheet(slot: _slot, ad: ad),
    );
    if (saved == true) _load();
    AdvertisementService.clearCache();
  }

  Future<void> _deleteAd(Advertisement ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove ad?'),
        content: Text('"${ad.title}" will be removed from this slot.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalKioskStore.instance.removeLocalAd(_slot, ad.id);
    AdvertisementService.clearCache();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final online = OfflineSyncService.instance.isOnline;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add ad'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(Icons.cloud_off_rounded, color: cs.primary),
              content: const Text(
                'Offline mode — ads are stored on this device.',
              ),
              backgroundColor: cs.primaryContainer.withValues(alpha: 0.35),
              actions: const [SizedBox.shrink()],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<AdSlot>(
              segments: const [
                ButtonSegment(
                  value: AdSlot.screensaver,
                  label: Text('Idle'),
                  icon: Icon(Icons.tv_rounded, size: 18),
                ),
                ButtonSegment(
                  value: AdSlot.top,
                  label: Text('Top'),
                  icon: Icon(Icons.view_column_rounded, size: 18),
                ),
                ButtonSegment(
                  value: AdSlot.externalScreen,
                  label: Text('External'),
                  icon: Icon(Icons.monitor_rounded, size: 18),
                ),
              ],
              selected: {_slot},
              onSelectionChanged: (s) {
                setState(() => _slot = s.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : _ads.isEmpty
                    ? Center(
                        child: Text(
                          'No ads in this slot.\nTap Add ad to create one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: cs.primary,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _ads.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final ad = _ads[i];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(
                                    ad.type == AdMediaType.video
                                        ? Icons.videocam_rounded
                                        : Icons.image_rounded,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                                title: Text(ad.title),
                                subtitle: Text(
                                  adMediaLabel(ad.mediaUrl),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      _openForm(ad: ad);
                                    } else if (v == 'delete') {
                                      _deleteAd(ad);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Remove'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AdFormSheet extends StatefulWidget {
  const _AdFormSheet({required this.slot, this.ad});
  final AdSlot slot;
  final Advertisement? ad;

  @override
  State<_AdFormSheet> createState() => _AdFormSheetState();
}

class _AdFormSheetState extends State<_AdFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _linkCtrl;
  late final TextEditingController _orderCtrl;
  late AdMediaType _type;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final ad = widget.ad;
    _titleCtrl = TextEditingController(text: ad?.title ?? '');
    _urlCtrl = TextEditingController(text: ad?.mediaUrl ?? '');
    _linkCtrl = TextEditingController(text: ad?.linkUrl ?? '');
    _orderCtrl = TextEditingController(
      text: '${ad?.sortOrder ?? 0}',
    );
    _type = ad?.type ?? AdMediaType.image;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _linkCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLocalImage() async {
    setState(() => _picking = true);
    try {
      final uri = await LocalAdMediaService.pickAndImportImage();
      if (uri != null) {
        _urlCtrl.text = uri;
        if (_type != AdMediaType.image) _type = AdMediaType.image;
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final id = widget.ad?.id ??
        LocalKioskStore.instance.nextLocalAdId();
    final ad = Advertisement(
      id: id,
      title: title,
      type: _type,
      mediaUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      linkUrl: _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
      sortOrder: int.tryParse(_orderCtrl.text.trim()) ?? 0,
    );

    await LocalKioskStore.instance.upsertLocalAd(widget.slot, ad);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.ad == null ? 'New ad' : 'Edit ad',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AdMediaType>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AdMediaType.image,
                    child: Text('Image'),
                  ),
                  DropdownMenuItem(
                    value: AdMediaType.video,
                    child: Text('Video'),
                  ),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 12),
              Text(
                'Media',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _picking ? null : _pickLocalImage,
                icon: _picking
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.photo_library_rounded),
                label: Text(
                  _picking ? 'Opening…' : 'Choose image from device',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Or paste URL / asset path',
                  hintText: 'https://… or assets/images/vmfs-logo.jpg',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_urlCtrl.text.trim().isNotEmpty &&
                  _type == AdMediaType.image) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: AdMediaImage(
                      mediaUrl: _urlCtrl.text.trim(),
                      error: Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Text(
                          'Preview unavailable',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _linkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link URL (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _orderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort order',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: cs.primary,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
