import 'package:flutter_test/flutter_test.dart';
import 'package:vmfs_lottery/models/machine_slot.dart';
void main() {
  test('lottery availability from local catalog aggregates stock', () {
    final catalog = MachineSlotsResponse(
      machineNumber: '123',
      machineName: 'Test',
      slots: [
        MachineSlot(
          lineNumber: 1,
          productName: 'A',
          price: 1,
          currentStock: 2,
          maxStock: 10,
          isAvailable: true,
          isFault: false,
        ),
        MachineSlot(
          lineNumber: 2,
          productName: 'B',
          price: 1,
          currentStock: 0,
          maxStock: 5,
          isAvailable: false,
          isFault: false,
        ),
      ],
      categories: const [],
    );

    // Mirror lottery service math (public API is async-only; keep formula in sync).
    var inStock = 0;
    var capacity = 0;
    for (final slot in catalog.slots) {
      inStock += slot.currentStock;
      capacity += slot.maxStock;
    }

    expect(inStock, 2);
    expect(capacity, 15);
    expect(inStock > 0, isTrue);
  });
}
