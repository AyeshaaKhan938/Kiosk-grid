/// Tipo de medio del anuncio.
enum AdMediaType { image, video, html }

/// Slot / posición del anuncio en la máquina.
enum AdSlot { screensaver, top, externalScreen }

/// Un anuncio individual (imagen, vídeo o HTML).
class Advertisement {
  final int id;
  final String title;
  final AdMediaType type;

  /// URL absoluta al archivo (imagen/vídeo) o null si es HTML embebido.
  final String? mediaUrl;

  /// URL opcional al que navegar al tocar el anuncio.
  final String? linkUrl;

  final int sortOrder;

  const Advertisement({
    required this.id,
    required this.title,
    required this.type,
    this.mediaUrl,
    this.linkUrl,
    required this.sortOrder,
  });

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'image';
    AdMediaType mediaType;
    switch (typeStr) {
      case 'video':
        mediaType = AdMediaType.video;
        break;
      case 'html':
        mediaType = AdMediaType.html;
        break;
      default:
        mediaType = AdMediaType.image;
    }

    return Advertisement(
      id:        (json['id'] as num).toInt(),
      title:     json['title'] as String? ?? '',
      type:      mediaType,
      mediaUrl:  json['media_url'] as String?,
      linkUrl:   json['link_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': switch (type) {
          AdMediaType.video => 'video',
          AdMediaType.html => 'html',
          AdMediaType.image => 'image',
        },
        'media_url': mediaUrl,
        'link_url': linkUrl,
        'sort_order': sortOrder,
      };
}

/// Respuesta completa del endpoint GET /machines/{no}/advertisements.
class AdvertisementsResponse {
  final int? groupId;
  final String? groupName;
  final List<Advertisement> screensaver;
  final List<Advertisement> top;
  final List<Advertisement> externalScreen;

  const AdvertisementsResponse({
    this.groupId,
    this.groupName,
    required this.screensaver,
    required this.top,
    required this.externalScreen,
  });

  bool get isEmpty =>
      screensaver.isEmpty && top.isEmpty && externalScreen.isEmpty;

  factory AdvertisementsResponse.fromJson(Map<String, dynamic> json) {
    List<Advertisement> _parseSlot(dynamic raw) {
      if (raw == null) return [];
      return (raw as List)
          .map((e) => Advertisement.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final slots = json['slots'] as Map<String, dynamic>? ?? {};

    return AdvertisementsResponse(
      groupId:        json['group_id'] as int?,
      groupName:      json['group_name'] as String?,
      screensaver:    _parseSlot(slots['screensaver']),
      top:            _parseSlot(slots['top']),
      externalScreen: _parseSlot(slots['external_screen']),
    );
  }

  /// Fallback vacío cuando la máquina no tiene grupo de anuncios.
  static const empty = AdvertisementsResponse(
    screensaver:    [],
    top:            [],
    externalScreen: [],
  );

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'group_name': groupName,
        'slots': {
          'screensaver': screensaver.map((e) => e.toJson()).toList(),
          'top': top.map((e) => e.toJson()).toList(),
          'external_screen': externalScreen.map((e) => e.toJson()).toList(),
        },
      };
}
