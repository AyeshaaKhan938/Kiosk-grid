/// Physical delivery mechanism of the cabinet — drives which admin
/// test tools are shown. Derived from [AppConfig.hardwareProtocol].
enum MachineMechanism {
  elevator,
  coil,
  conveyor,
  cooler;

  static MachineMechanism fromHardwareProtocol(String protocol) {
    switch (protocol) {
      case 'tcn':
        return MachineMechanism.coil;
      case 'conveyor':
        return MachineMechanism.conveyor;
      case 'bket':
        return MachineMechanism.cooler;
      case 'afen':
      case 'uart':
      case 'reyeah':
      default:
        return MachineMechanism.elevator;
    }
  }

  String get label {
    switch (this) {
      case MachineMechanism.elevator:
        return 'Elevator / lift';
      case MachineMechanism.coil:
        return 'Coil / spiral';
      case MachineMechanism.conveyor:
        return 'Conveyor belt';
      case MachineMechanism.cooler:
        return 'AI cooler';
    }
  }

  String get shortLabel {
    switch (this) {
      case MachineMechanism.elevator:
        return 'Elevator';
      case MachineMechanism.coil:
        return 'Coil';
      case MachineMechanism.conveyor:
        return 'Conveyor';
      case MachineMechanism.cooler:
        return 'Cooler';
    }
  }

  bool get hasLiftPlatform => this == MachineMechanism.elevator;

  bool get usesSerialTty =>
      this == MachineMechanism.elevator ||
      this == MachineMechanism.coil ||
      this == MachineMechanism.conveyor;
}
