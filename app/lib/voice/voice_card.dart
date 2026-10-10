/// A result card on the voice screen (weather, media, image or any entity), built by the Home Assistant integration
/// (custom_components/ha_sidecar/cards.py) and rendered by the page and by the native docked card.
class ForecastDay {
  const ForecastDay({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final String icon;
}

class VoiceCard {
  const VoiceCard({
    required this.type,
    this.title = '',
    this.subtitle = '',
    this.value = '',
    this.icon = 'info',
    this.image = '',
    this.details = const [],
    this.forecast = const [],
    this.entityId = '',
  });

  /// `weather`, `media`, `image` or `entity`.
  final String type;
  final String title;
  final String subtitle;
  final String value;

  /// A key both renderers know (`sunny`, `rainy`, `light`, `media`, `camera`, `info`, ...).
  final String icon;

  /// An absolute URL the tablet can fetch (the controller has rebased a path on Home Assistant), or empty.
  final String image;
  final List<String> details;
  final List<ForecastDay> forecast;
  final String entityId;

  static const types = {'weather', 'media', 'image', 'entity'};

  /// Parses a card from the wire; [url] turns an image path into one the tablet can fetch (null drops the image).
  /// Returns null for anything that is not a card.
  static VoiceCard? fromJson(Object? raw, {String? Function(String)? url}) {
    if (raw is! Map) return null;
    String s(String k) => '${raw[k] ?? ''}';
    final type = types.contains(raw['type']) ? '${raw['type']}' : 'entity';
    final image = s('image');
    final card = VoiceCard(
      type: type,
      title: s('title'),
      subtitle: s('subtitle'),
      value: s('value'),
      icon: raw['icon'] == null || s('icon').isEmpty ? 'info' : s('icon'),
      image: image.isEmpty ? '' : (url == null ? image : (url(image) ?? '')),
      details: [
        if (raw['details'] case final List d)
          for (final x in d) '$x',
      ],
      forecast: [
        if (raw['forecast'] case final List days)
          for (final f in days)
            if (f is Map)
              ForecastDay(
                label: '${f['label'] ?? ''}',
                value: '${f['value'] ?? ''}',
                icon: '${f['icon'] ?? 'cloudy'}',
              ),
      ],
      entityId: s('entity_id'),
    );
    final empty =
        card.title.isEmpty &&
        card.value.isEmpty &&
        card.image.isEmpty &&
        card.subtitle.isEmpty;
    return empty ? null : card;
  }

  /// For the native docked card.
  Map<String, Object?> toSnapshot() => {
    'type': type,
    'title': title,
    'subtitle': subtitle,
    'value': value,
    'icon': icon,
    'image': image,
    'details': details,
    'forecast': [
      for (final f in forecast)
        {'label': f.label, 'value': f.value, 'icon': f.icon},
    ],
  };
}
