import 'dart:typed_data';

/// Stateful stream-to-frame splitter for the Reyeah UART protocol —
/// Dart equivalent of factory.apk's `AbsStickPackageHelper`
/// / `VariableLenStickPackageHelper`.
///
/// Background bytes arrive from the kernel TTY layer in arbitrary
/// chunks: sometimes the full frame, sometimes only a header, sometimes
/// two frames concatenated. We accumulate into an internal buffer and
/// extract complete, checksum-verified frames as they become available.
///
/// Frame format (App→VMC is 0x55, VMC→App is 0xAA):
///   [0xFF ADDR] [0x00 FRAME_NUM] [HEADER] [CMD] [DATA_LEN] [DATA..] [CHK]
///   CHK = (HEADER + CMD + DATA_LEN + sum(DATA)) & 0xFF
///         (excludes ADDR + FRAME_NUM)
///
/// Use:
///   final asm = SerialFrameAssembler();
///   for (final rawChunk in fromTtyStream) {
///     for (final frame in asm.feed(rawChunk)) {
///       handleFrame(frame);
///     }
///   }
class SerialFrameAssembler {
  /// Address byte the frame must start with.
  static const int _addrByte = 0xFF;

  /// Header bytes we accept (VMC→App responses). App→VMC writes use
  /// 0x55 — the buildFrame helpers in vending_machine_service handle
  /// outgoing frames; this class is only for parsing incoming bytes.
  static const _acceptedHeaders = <int>{0x55, 0xAA};

  /// Maximum data-length byte we'll trust before considering the
  /// buffer corrupt. The Reyeah protocol's longest legitimate frame
  /// is well under this; values above are almost always us misaligned
  /// on noise.
  static const int _maxDataLen = 64;

  final List<int> _buf = [];

  /// Number of bytes we discarded because the first byte wasn't a
  /// frame start. Exposed for diagnostics (a high value means UART
  /// noise or a baud mismatch).
  int discardedBytes = 0;

  /// Append [chunk] to the internal buffer and return every complete
  /// frame that's been assembled so far. Mutates internal state.
  List<Uint8List> feed(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    _buf.addAll(chunk);
    final frames = <Uint8List>[];
    Uint8List? next;
    while ((next = _tryExtractOne()) != null) {
      frames.add(next!);
    }
    return frames;
  }

  /// Discard any partial frame in progress. Use after a hard reset
  /// (port reopen, dispense failure, etc.) to avoid carrying noise
  /// into the next session.
  void reset() {
    _buf.clear();
    discardedBytes = 0;
  }

  Uint8List? _tryExtractOne() {
    // Strip leading noise until we land on an ADDR byte.
    while (_buf.isNotEmpty && _buf.first != _addrByte) {
      _buf.removeAt(0);
      discardedBytes++;
    }
    // Minimum legal frame: ADDR + FRAME_NUM + HEADER + CMD + LEN + CHK = 6
    if (_buf.length < 6) return null;

    final header = _buf[2];
    if (!_acceptedHeaders.contains(header)) {
      // Misaligned — skip the ADDR byte and let the loop above find
      // the next candidate. Could also be a different protocol entirely.
      _buf.removeAt(0);
      discardedBytes++;
      return null;
    }

    final dataLen = _buf[4];
    if (dataLen > _maxDataLen) {
      // Length byte is unbelievable — treat as misalignment.
      _buf.removeAt(0);
      discardedBytes++;
      return null;
    }

    final totalLen = 5 + dataLen + 1; // ADDR FRAME HEADER CMD LEN + data + CHK
    if (_buf.length < totalLen) return null; // wait for more bytes

    final candidate = Uint8List.fromList(_buf.sublist(0, totalLen));
    final ok = _validateChecksum(candidate);
    if (!ok) {
      // Bad checksum — drop one byte and try realigning.
      _buf.removeAt(0);
      discardedBytes++;
      return null;
    }

    _buf.removeRange(0, totalLen);
    return candidate;
  }

  /// CHK = (HEADER + CMD + DATA_LEN + sum(DATA)) & 0xFF
  /// (excludes ADDR + FRAME_NUM per protocol)
  static bool _validateChecksum(Uint8List frame) {
    if (frame.length < 6) return false;
    final dataLen = frame[4];
    if (frame.length != 5 + dataLen + 1) return false;
    var sum = frame[2] + frame[3] + frame[4];
    for (var i = 5; i < 5 + dataLen; i++) {
      sum += frame[i];
    }
    return (sum & 0xFF) == frame[5 + dataLen];
  }
}
