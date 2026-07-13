import 'dart:convert';
import 'dart:typed_data';

import 'app_config.dart';
import 'log_file_util.dart';
import 'tty_serial.dart';

/// TCN vending machine serial protocol (Integration via UART text commands).
///
/// TCN Android boards use `$$$|...|%%%` framed commands over serial.
/// Reference: TCN elevator/spiral machine user manuals + tcn_serial plugin.
class TcnSerialService {
  /// Dispense one unit from [slotNo] (coil / cargo lane number).
  ///
  /// Command format (TCN standard Android back-end):
  ///   `$$$|D|<slot>|1|0|255|%%%`
  static Future<bool> shipment(int slotNo) async {
    final cmd = '${r'$$$|D|'}$slotNo|1|0|255|%%%';
    return _sendCommand(cmd, label: 'shipment slot $slotNo');
  }

  /// Query slot configuration (new control board).
  static Future<String> querySlotsNewBoard() async {
    return _sendCommandRaw(r'$$$|C|315|%%%', label: 'query slots (new board)');
  }

  /// Query slot configuration (old control board).
  static Future<String> querySlotsOldBoard() async {
    return _sendCommandRaw(r'$$$|F|70|%%%', label: 'query slots (old board)');
  }

  /// Clear elevator fault (TCN lift machines).
  static Future<bool> clearElevatorFault() async {
    final cmd = AppConfig.tcnClearFaultCommand;
    if (cmd.isEmpty) return false;
    return _sendCommand(cmd, label: 'clear fault');
  }

  static Future<bool> _sendCommand(String command, {required String label}) async {
    final response = await _sendCommandRaw(command, label: label);
    if (response.isEmpty) return false;
    final lower = response.toLowerCase();
    if (lower.contains('fail') || lower.contains('error')) return false;
    return true;
  }

  static Future<String> _sendCommandRaw(
    String command, {
    required String label,
  }) async {
    final path = AppConfig.ttyPath;
    final baud = AppConfig.tcnSerialBaud;

    await LogFileUtil.i('tcn.serial.$label', {'cmd': command, 'path': path});

    try {
      await TtySerial.open(path, baud: baud);
      await TtySerial.write(Uint8List.fromList(utf8.encode(command)));
      await Future.delayed(const Duration(milliseconds: 300));
      final response = await TtySerial.read(
        timeout: const Duration(milliseconds: 2500),
      );
      await TtySerial.close();
      final text = utf8.decode(response, allowMalformed: true).trim();
      await LogFileUtil.i('tcn.serial.response', {'label': label, 'raw': text});
      return text;
    } catch (e) {
      await LogFileUtil.e('tcn.serial.error', error: e);
      try {
        await TtySerial.close();
      } catch (_) {}
      rethrow;
    }
  }
}
