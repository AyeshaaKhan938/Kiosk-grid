enum MachineIssueComponent {
  screen('screen'),
  elevator('elevator'),
  powerSupply('power_supply'),
  payment('payment'),
  pusher('pusher'),
  motor('motor'),
  connectivity('connectivity'),
  temperature('temperature'),
  door('door'),
  dispense('dispense'),
  other('other');

  const MachineIssueComponent(this.apiValue);

  final String apiValue;
}

enum MachineIssueSeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  const MachineIssueSeverity(this.apiValue);

  final String apiValue;
}
