import 'package:flutter/material.dart';

import '../services/accessibility_settings.dart';

/// Accessibility controls (text size, high contrast) — opened from the top bar.
class AccessibilityOptionsPanel extends StatefulWidget {
  const AccessibilityOptionsPanel({super.key});

  @override
  State<AccessibilityOptionsPanel> createState() =>
      _AccessibilityOptionsPanelState();
}

class _AccessibilityOptionsPanelState extends State<AccessibilityOptionsPanel> {
  final _settings = AccessibilitySettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_rebuild);
  }

  @override
  void dispose() {
    _settings.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hc = _settings.highContrast;
    final accent = hc ? const Color(0xFFFFD700) : const Color(0xFF007ACC);
    final panelBg = hc ? const Color(0xFF1A1A1A) : Colors.white;
    final panelBorder = hc ? const Color(0xFFFFD700) : Colors.black12;
    final labelColor = hc ? Colors.white : Colors.black87;
    final subColor = hc ? Colors.white70 : Colors.black54;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('♿', style: TextStyle(fontSize: 20, color: accent)),
              const SizedBox(width: 8),
              Text(
                'Accessibility',
                style: TextStyle(
                  color: labelColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: subColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Text size',
            style: TextStyle(
              color: subColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _TextSizeRow(
            accent: accent,
            labelColor: labelColor,
            panelBg: panelBg,
            hc: hc,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'High contrast',
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Black background, yellow text',
                      style: TextStyle(color: subColor, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: hc,
                activeTrackColor: accent.withValues(alpha: 0.55),
                onChanged: (_) => _settings.toggleHighContrast(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: panelBorder, height: 1),
          const SizedBox(height: 12),
          Text(
            'Screen reader',
            style: TextStyle(
              color: subColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hc ? const Color(0xFF2A2A2A) : const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Android: Settings → Accessibility → TalkBack',
              style: TextStyle(color: subColor, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

void showAccessibilityOptionsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final hc = AccessibilitySettings.instance.highContrast;
      return Material(
        color: hc ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: const AccessibilityOptionsPanel(),
      );
    },
  );
}

class _TextSizeRow extends StatelessWidget {
  final Color accent;
  final Color labelColor;
  final Color panelBg;
  final bool hc;

  const _TextSizeRow({
    required this.accent,
    required this.labelColor,
    required this.panelBg,
    required this.hc,
  });

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilitySettings.instance;
    final current = settings.textScale;

    const options = [
      (1.0, 'Normal'),
      (1.25, 'Large'),
      (1.5, 'X-Large'),
    ];

    return Row(
      children: options.asMap().entries.map((entry) {
        final idx = entry.key;
        final scale = entry.value.$1;
        final label = entry.value.$2;
        final selected = current == scale;
        final fontSize = 14.0 + idx * 3.0;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: idx < 2 ? 8 : 0),
            child: Material(
              color: selected ? accent.withValues(alpha: 0.15) : panelBg,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => settings.setTextScale(scale),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? accent : Colors.black26,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'A',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: selected ? accent : labelColor,
                        ),
                      ),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: selected
                              ? accent
                              : labelColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
