import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Layout style for [OnScreenKeypad].
enum KeypadMode {
  /// 0-9 only. Used for PINs and slot numbers.
  numeric,

  /// 0-9 plus a decimal point. Used for prices.
  numericDecimal,

  /// Full alphanumeric — digits row + QWERTY letters + backspace + enter.
  /// Used for codes, tokens, search fields, machine numbers, etc.
  alphanumeric,
}

/// Reusable on-screen keypad.
///
/// Reyeah's kiosk tablets ship with no system IME installed, so a
/// `TextField` alone never shows a keyboard for the customer or
/// technician. This widget is the entire input surface for the kiosk:
/// the customer-facing lottery code screen embeds it inline, and the
/// admin-side `TextField`s open it inside a modal bottom sheet via
/// [showKeypad].
class OnScreenKeypad extends StatelessWidget {
  final TextEditingController controller;
  final KeypadMode mode;
  final double scale;
  final bool enabled;
  final int? maxLength;

  /// Fires after every character append / backspace. Use for clearing
  /// inline error state or driving live previews.
  final VoidCallback? onChanged;

  /// Fires when the user taps the big red ENTER key. If null, no ENTER
  /// row is rendered. The keypad does not itself dismiss anything on
  /// submit — the caller decides what ENTER means in context.
  final VoidCallback? onSubmit;

  /// Label shown on the ENTER key. Defaults to "ENTER" but you can pass
  /// "DONE" / "SAVE" / etc. when the keypad lives inside a modal.
  final String submitLabel;

  const OnScreenKeypad({
    super.key,
    required this.controller,
    this.mode = KeypadMode.alphanumeric,
    this.scale = 320,
    this.enabled = true,
    this.maxLength,
    this.onChanged,
    this.onSubmit,
    this.submitLabel = 'ENTER',
  });

  static const _letterRow2 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
  static const _letterRow3 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
  static const _letterRow4 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];
  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

  void _append(String ch) {
    final t = controller.text;
    if (maxLength != null && t.length >= maxLength!) return;
    final newText = t + ch;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    onChanged?.call();
  }

  void _backspace() {
    final t = controller.text;
    if (t.isEmpty) return;
    final newText = t.substring(0, t.length - 1);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case KeypadMode.numeric:
        return _buildNumeric(withDecimal: false);
      case KeypadMode.numericDecimal:
        return _buildNumeric(withDecimal: true);
      case KeypadMode.alphanumeric:
        return _buildAlphanumeric();
    }
  }

  // ── shared cell builder ──────────────────────────────────────────────

  Widget _keyCell({
    required double keyH,
    required double gap,
    required double radius,
    required double font,
    String? label,
    Widget? child,
    int flex = 1,
    Color? bg,
    VoidCallback? onTap,
  }) {
    final defaultTap = label != null ? () => _append(label) : null;
    final effectiveTap = enabled ? (onTap ?? defaultTap) : null;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.all(gap / 2),
        child: SizedBox(
          height: keyH,
          child: Material(
            color: bg ?? Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: effectiveTap,
              borderRadius: BorderRadius.circular(radius),
              child: Center(
                child: child ??
                    Text(
                      label ?? '',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: font,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Numeric layout ───────────────────────────────────────────────────
  //
  //   1 2 3
  //   4 5 6
  //   7 8 9
  //   . 0 ⌫   (or [blank] 0 ⌫ for non-decimal)
  //   [ENTER] ← optional, full-width
  //
  Widget _buildNumeric({required bool withDecimal}) {
    final keyH = scale * 0.105;
    final gap = scale * 0.012;
    final radius = scale * 0.014;
    final font = scale * 0.065;

    Widget cell({
      String? label,
      Widget? child,
      int flex = 1,
      Color? bg,
      VoidCallback? onTap,
    }) =>
        _keyCell(
          keyH: keyH,
          gap: gap,
          radius: radius,
          font: font,
          label: label,
          child: child,
          flex: flex,
          bg: bg,
          onTap: onTap,
        );

    Widget blankCell() => cell(
          // Decorative placeholder so the layout stays a clean 3-col grid
          // when there's no decimal. Tap is a no-op.
          child: const SizedBox.shrink(),
          onTap: () {},
          bg: Colors.transparent,
        );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [cell(label: '1'), cell(label: '2'), cell(label: '3')]),
          Row(children: [cell(label: '4'), cell(label: '5'), cell(label: '6')]),
          Row(children: [cell(label: '7'), cell(label: '8'), cell(label: '9')]),
          Row(children: [
            withDecimal ? cell(label: '.') : blankCell(),
            cell(label: '0'),
            cell(
              bg: Colors.white.withValues(alpha: 0.18),
              onTap: _backspace,
              child: Icon(Icons.backspace_outlined,
                  color: Colors.white, size: font * 0.9),
            ),
          ]),
          if (onSubmit != null)
            Row(children: [
              cell(
                flex: 3,
                bg: const Color(0xFFD32F2F),
                onTap: onSubmit,
                child: Text(
                  submitLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: font * 0.55,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  // ── Alphanumeric layout ──────────────────────────────────────────────
  //
  //   1 2 3 4 5 6 7 8 9 0
  //   Q W E R T Y U I O P
  //   A S D F G H J K L  ⌫
  //   Z X C V B N M  [ENTER ............]
  //
  Widget _buildAlphanumeric() {
    final keyH = scale * 0.105;
    final gap = scale * 0.010;
    final radius = scale * 0.012;
    final font = scale * 0.052;

    Widget cell({
      String? label,
      Widget? child,
      int flex = 1,
      Color? bg,
      VoidCallback? onTap,
    }) =>
        _keyCell(
          keyH: keyH,
          gap: gap,
          radius: radius,
          font: font,
          label: label,
          child: child,
          flex: flex,
          bg: bg,
          onTap: onTap,
        );

    Row letters(List<String> chars) =>
        Row(children: [for (final c in chars) cell(label: c)]);

    return Padding(
      padding: EdgeInsets.only(top: scale * 0.012),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          letters(_digits),
          letters(_letterRow2),
          Row(children: [
            for (final c in _letterRow3) cell(label: c),
            cell(
              bg: Colors.white.withValues(alpha: 0.18),
              onTap: _backspace,
              child: Icon(Icons.backspace_outlined,
                  color: Colors.white, size: font * 1.1),
            ),
          ]),
          Row(children: [
            for (final c in _letterRow4) cell(label: c),
            if (onSubmit != null)
              cell(
                flex: 3,
                bg: const Color(0xFFD32F2F),
                onTap: onSubmit,
                // FittedBox + single line: the label scales down to fit the
                // key width instead of wrapping to "ENTE"/"R" on narrower
                // panels. Horizontal padding keeps it off the rounded edges.
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: font * 0.3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      submitLabel,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: font * 0.7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              )
            else
              cell(
                flex: 3,
                bg: Colors.transparent,
                onTap: () {},
                child: const SizedBox.shrink(),
              ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared panel chrome — same look for admin bottom sheets and customer popups.
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps [OnScreenKeypad] in the standard VMFS dark-blue panel with optional
/// preview field, drag handle, and cancel action.
class KeypadPanel extends StatelessWidget {
  final TextEditingController controller;
  final KeypadMode mode;
  final int? maxLength;
  final bool enabled;
  final String? title;
  final String? hint;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final VoidCallback? onChanged;
  final VoidCallback? onCancel;
  final bool showPreview;
  final bool obscurePreview;
  final bool showDragHandle;
  final BorderRadius borderRadius;
  final double? width;
  final double? scale;

  const KeypadPanel({
    super.key,
    required this.controller,
    this.mode = KeypadMode.alphanumeric,
    this.maxLength,
    this.enabled = true,
    this.title,
    this.hint,
    this.submitLabel = 'ENTER',
    this.onSubmit,
    this.onChanged,
    this.onCancel,
    this.showPreview = true,
    this.obscurePreview = false,
    this.showDragHandle = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.width,
    this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final keypadScale = scale ?? math.min(size.width, size.height / 1.6);

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A2B),
        borderRadius: borderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDragHandle)
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: Color(0xFF007ACC),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (showPreview) ...[
            ListenableBuilder(
              listenable: controller,
              builder: (_, __) {
                final raw = controller.text;
                final display =
                    obscurePreview ? '•' * raw.length : raw;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060E18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          display.isEmpty ? (hint ?? '') : display,
                          style: TextStyle(
                            color: display.isEmpty
                                ? Colors.white24
                                : Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: mode == KeypadMode.alphanumeric
                                ? null
                                : 'monospace',
                            letterSpacing: obscurePreview ? 6 : 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (maxLength != null)
                        Text(
                          '${controller.text.length}/$maxLength',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          OnScreenKeypad(
            controller: controller,
            mode: mode,
            maxLength: maxLength,
            scale: keypadScale,
            enabled: enabled,
            submitLabel: submitLabel,
            onChanged: onChanged,
            onSubmit: onSubmit,
          ),
          if (onCancel != null)
            Center(
              child: TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modal helper — opens an [OnScreenKeypad] inside a bottom sheet over a
// staging controller, commits to the target controller on DONE.
// ─────────────────────────────────────────────────────────────────────────────

/// Show a modal-bottom-sheet keypad bound to [controller].
///
/// Edits happen on a *staging* controller so the user can hit Cancel
/// (tap outside / back button) without polluting the real value. When
/// they tap DONE the sheet pops with the staged text and we write it
/// to [controller]. [onCommitted] fires after the commit so callers
/// can run validation / setState.
Future<String?> showKeypad(
  BuildContext context, {
  required TextEditingController controller,
  KeypadMode mode = KeypadMode.alphanumeric,
  int? maxLength,
  bool obscureText = false,
  String? title,
  String? hint,
  String submitLabel = 'DONE',
  ValueChanged<String>? onCommitted,
}) async {
  final stagingCtrl = TextEditingController(text: controller.text);

  final committed = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => _KeypadSheet(
      staging: stagingCtrl,
      mode: mode,
      maxLength: maxLength,
      obscureText: obscureText,
      title: title,
      hint: hint,
      submitLabel: submitLabel,
    ),
  );

  if (committed != null) {
    controller.value = TextEditingValue(
      text: committed,
      selection: TextSelection.collapsed(offset: committed.length),
    );
    onCommitted?.call(committed);
  }
  stagingCtrl.dispose();
  return committed;
}

class _KeypadSheet extends StatefulWidget {
  final TextEditingController staging;
  final KeypadMode mode;
  final int? maxLength;
  final bool obscureText;
  final String? title;
  final String? hint;
  final String submitLabel;

  const _KeypadSheet({
    required this.staging,
    required this.mode,
    required this.maxLength,
    required this.obscureText,
    required this.title,
    required this.hint,
    required this.submitLabel,
  });

  @override
  State<_KeypadSheet> createState() => _KeypadSheetState();
}

class _KeypadSheetState extends State<_KeypadSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: KeypadPanel(
        controller: widget.staging,
        mode: widget.mode,
        maxLength: widget.maxLength,
        title: widget.title,
        hint: widget.hint,
        submitLabel: widget.submitLabel,
        obscurePreview: widget.obscureText,
        showDragHandle: true,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
        onSubmit: () => Navigator.of(context).pop(widget.staging.text),
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }
}
