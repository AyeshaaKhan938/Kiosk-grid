import 'package:flutter_test/flutter_test.dart';
import 'package:vmfs_lottery/models/machine_mechanism.dart';

void main() {
  group('MachineMechanism.fromHardwareProtocol', () {
    test('maps uart and afen to elevator', () {
      expect(
        MachineMechanism.fromHardwareProtocol('uart'),
        MachineMechanism.elevator,
      );
      expect(
        MachineMechanism.fromHardwareProtocol('afen'),
        MachineMechanism.elevator,
      );
    });

    test('maps tcn to coil', () {
      expect(
        MachineMechanism.fromHardwareProtocol('tcn'),
        MachineMechanism.coil,
      );
    });

    test('maps conveyor to conveyor', () {
      expect(
        MachineMechanism.fromHardwareProtocol('conveyor'),
        MachineMechanism.conveyor,
      );
    });

    test('maps bket to cooler', () {
      expect(
        MachineMechanism.fromHardwareProtocol('bket'),
        MachineMechanism.cooler,
      );
    });

    test('elevator has lift platform; coil and conveyor do not', () {
      expect(MachineMechanism.elevator.hasLiftPlatform, isTrue);
      expect(MachineMechanism.coil.hasLiftPlatform, isFalse);
      expect(MachineMechanism.conveyor.hasLiftPlatform, isFalse);
      expect(MachineMechanism.cooler.hasLiftPlatform, isFalse);
    });
  });
}
