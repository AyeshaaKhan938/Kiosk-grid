import 'package:flutter/material.dart';
import '../services/accessibility_settings.dart';

/// Botón flotante ♿ siempre visible. Al tocarlo abre un panel con opciones
/// de accesibilidad: tamaño de texto y modo alto contraste.
///
/// Se inyecta en el MaterialApp.builder para aparecer en TODAS las pantallas.
class AccessibilityFAB extends StatefulWidget {
  const AccessibilityFAB({super.key});

  @override
  State<AccessibilityFAB> createState() => _AccessibilityFABState();
}

class _AccessibilityFABState extends State<AccessibilityFAB>
    with SingleTickerProviderStateMixin {

  bool _panelOpen = false;
  late AnimationController _anim;
  late Animation<double>   _scaleAnim;
  late Animation<double>   _fadeAnim;

  final _settings = AccessibilitySettings.instance;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _scaleAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    _fadeAnim  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _settings.addListener(_rebuild);
  }

  @override
  void dispose() {
    _settings.removeListener(_rebuild);
    _anim.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _toggle() {
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) _anim.forward(); else _anim.reverse();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hc = _settings.highContrast;
    final btnBg   = hc ? const Color(0xFFFFD700) : const Color(0xFF007ACC);
    final btnIcon = hc ? Colors.black : Colors.white;

    return Positioned(
      bottom: 24,
      right:  24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Panel de opciones (aparece al abrir) ─────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              alignment: Alignment.bottomRight,
              child: _panelOpen ? _buildPanel(hc, btnBg) : const SizedBox(),
            ),
          ),
          const SizedBox(height: 12),

          // ── Botón flotante ♿ ─────────────────────────────────────────────
          Semantics(
            label: _panelOpen
                ? 'Close accessibility options'
                : 'Open accessibility options',
            button: true,
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  56,
                height: 56,
                decoration: BoxDecoration(
                  color: btnBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: btnBg.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '♿',
                    style: TextStyle(fontSize: 24, color: btnIcon),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Panel de opciones ─────────────────────────────────────────────────────

  Widget _buildPanel(bool hc, Color accent) {
    final panelBg     = hc ? const Color(0xFF1A1A1A) : Colors.white;
    final panelBorder = hc ? const Color(0xFFFFD700) : Colors.black12;
    final labelColor  = hc ? Colors.white : Colors.black87;
    final subColor    = hc ? Colors.white70 : Colors.black54;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: panelBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(children: [
            Text('♿', style: TextStyle(fontSize: 18, color: accent)),
            const SizedBox(width: 8),
            Text('Accessibility',
                style: TextStyle(
                    color: labelColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: _toggle,
              child: Icon(Icons.close_rounded, color: subColor, size: 18),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Tamaño de texto ─────────────────────────────────────────────
          Text('Text Size',
              style: TextStyle(color: subColor, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 8),
          _TextSizeRow(accent: accent, labelColor: labelColor,
              panelBg: panelBg, hc: hc),
          const SizedBox(height: 16),

          // ── Alto contraste ──────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('High Contrast',
                      style: TextStyle(color: labelColor, fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text('Black bg, yellow text',
                      style: TextStyle(color: subColor, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _settings.toggleHighContrast()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 26,
                decoration: BoxDecoration(
                  color: hc ? accent : Colors.black26,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: hc ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 20, height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: hc ? Colors.black : Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 16),
          Divider(color: panelBorder, height: 1),
          const SizedBox(height: 16),

          // ── Screen Reader ───────────────────────────────────────────────
          Text('Screen Reader',
              style: TextStyle(color: subColor, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hc
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.record_voice_over_rounded, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Text('TalkBack (Android)',
                      style: TextStyle(color: labelColor,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 6),
                Text(
                  'Settings → Accessibility\n→ TalkBack → Turn on',
                  style: TextStyle(color: subColor, fontSize: 11, height: 1.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Once active: swipe right/left to navigate, double-tap to select.',
                  style: TextStyle(color: subColor, fontSize: 10, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fila de botones de tamaño de texto ────────────────────────────────────────

class _TextSizeRow extends StatelessWidget {
  final Color accent;
  final Color labelColor;
  final Color panelBg;
  final bool  hc;
  const _TextSizeRow({
    required this.accent,
    required this.labelColor,
    required this.panelBg,
    required this.hc,
  });

  @override
  Widget build(BuildContext context) {
    final settings = AccessibilitySettings.instance;
    final current  = settings.textScale;

    final options = [
      (1.0,  'A',  'Normal'),
      (1.25, 'A',  'Large'),
      (1.5,  'A',  'X-Large'),
    ];

    return Row(
      children: options.asMap().entries.map((entry) {
        final idx      = entry.key;
        final scale    = entry.value.$1;
        final letter   = entry.value.$2;
        final label    = entry.value.$3;
        final selected = current == scale;
        final fontSize = 13.0 + idx * 3.0;  // A, A, A — each bigger

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: idx < 2 ? 6 : 0),
            child: Semantics(
              label: 'Text size $label',
              button: true,
              selected: selected,
              child: GestureDetector(
                onTap: () => settings.setTextScale(scale),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? accent.withValues(alpha: 0.15) : panelBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? accent : Colors.black26,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(letter,
                          style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              color: selected ? accent : labelColor)),
                      Text(label,
                          style: TextStyle(
                              fontSize: 8,
                              color: selected ? accent : labelColor.withValues(alpha: 0.6))),
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
