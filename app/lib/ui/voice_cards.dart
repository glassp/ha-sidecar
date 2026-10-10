import 'package:flutter/material.dart';

import '../voice/voice_card.dart';

/// The icon for a card or forecast key (the same keys the native docked card maps to glyphs).
IconData cardIcon(String key) => switch (key) {
  'sunny' => Icons.wb_sunny_outlined,
  'clear-night' => Icons.nightlight_outlined,
  'partlycloudy' => Icons.cloud_queue,
  'cloudy' => Icons.cloud_outlined,
  'rainy' => Icons.water_drop_outlined,
  'pouring' => Icons.umbrella_outlined,
  'snowy' => Icons.ac_unit,
  'lightning' => Icons.flash_on,
  'fog' => Icons.blur_on,
  'windy' => Icons.air,
  'exceptional' => Icons.warning_amber_outlined,
  'media' => Icons.music_note,
  'light' => Icons.lightbulb_outline,
  'switch' => Icons.power_settings_new,
  'cover' => Icons.blinds,
  'lock' => Icons.lock_outline,
  'climate' => Icons.thermostat,
  'fan' => Icons.mode_fan_off_outlined,
  'vacuum' => Icons.cleaning_services_outlined,
  'sensor' => Icons.sensors,
  'camera' => Icons.photo_camera_outlined,
  'person' => Icons.person_outline,
  _ => Icons.info_outline,
};

/// The result cards of one turn, under the answer.
class ResultCards extends StatelessWidget {
  const ResultCards(this.cards, {super.key});
  final List<VoiceCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cards)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ResultCard(c),
          ),
      ],
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard(this.card, {super.key});
  final VoiceCard card;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('card-${card.type}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: s.outline.withValues(alpha: 0.6)),
      ),
      child: switch (card.type) {
        'weather' => _Weather(card),
        'media' => _Media(card),
        'image' => _Picture(card),
        _ => _Entity(card),
      },
    );
  }
}

class _Weather extends StatelessWidget {
  const _Weather(this.card);
  final VoiceCard card;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final info = Row(
      children: [
        Icon(cardIcon(card.icon), size: 52, color: s.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.title,
                style: t.labelLarge?.copyWith(color: s.onSurfaceVariant),
              ),
              if (card.value.isNotEmpty)
                Text(card.value, style: t.headlineMedium),
              Text(
                card.subtitle,
                style: t.bodyLarge?.copyWith(color: s.onSurfaceVariant),
              ),
              if (card.details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    card.details.join('  ·  '),
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    final days = [
      for (final f in card.forecast)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              f.label,
              style: t.labelMedium?.copyWith(color: s.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Icon(cardIcon(f.icon), size: 24, color: s.secondary),
            const SizedBox(height: 4),
            Text(f.value, style: t.labelMedium),
          ],
        ),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      // beside each other on a tablet, the forecast under the text on a phone (four days would leave the text no room)
      child: LayoutBuilder(
        builder: (context, box) {
          if (days.isEmpty) return info;
          if (box.maxWidth < 560) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                info,
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  spacing: 14,
                  runSpacing: 10,
                  children: days,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              for (final d in days)
                Padding(padding: const EdgeInsets.only(left: 14), child: d),
            ],
          );
        },
      ),
    );
  }
}

class _Media extends StatelessWidget {
  const _Media(this.card);
  final VoiceCard card;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: card.image.isEmpty
              ? Container(
                  color: s.surfaceContainerHighest,
                  child: Icon(Icons.music_note, size: 36, color: s.primary),
                )
              : _NetworkImage(
                  card.image,
                  fit: BoxFit.cover,
                  fallback: Icons.music_note,
                ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium,
                ),
                Text(
                  card.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                ),
                if (card.value.isNotEmpty)
                  Text(
                    card.value,
                    style: t.labelMedium?.copyWith(color: s.primary),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture(this.card);
  final VoiceCard card;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.image.isNotEmpty)
          SizedBox(
            height: 220,
            child: _NetworkImage(
              card.image,
              fit: BoxFit.cover,
              fallback: Icons.photo_camera_outlined,
            ),
          ),
        if (card.title.isNotEmpty || card.subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(cardIcon(card.icon), size: 20, color: s.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(card.title, style: t.titleSmall)),
                if (card.subtitle.isNotEmpty)
                  Text(
                    card.subtitle,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Entity extends StatelessWidget {
  const _Entity(this.card);
  final VoiceCard card;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(cardIcon(card.icon), size: 30, color: s.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title, style: t.titleMedium),
                if (card.subtitle.isNotEmpty)
                  Text(
                    card.subtitle,
                    style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                  ),
                for (final d in card.details)
                  Text(
                    d,
                    style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (card.value.isNotEmpty) Text(card.value, style: t.headlineSmall),
        ],
      ),
    );
  }
}

/// A picture from a URL; an icon instead while it loads or when it cannot be loaded.
class _NetworkImage extends StatelessWidget {
  const _NetworkImage(this.url, {required this.fit, required this.fallback});
  final String url;
  final BoxFit fit;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
      color: s.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(fallback, size: 36, color: s.onSurfaceVariant),
    );
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder(),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder(),
    );
  }
}
