import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/interactive_slot/slot_config.dart';
import 'package:infinite_calendar_view/src/interactive_slot/slot_selection.dart';

void main() {
  const config = SlotInteractionConfig(stepMinutes: 15);
  final anchor = CalendarSlot(
    columnIndex: 0,
    initialStartDate: DateTime(2026, 7, 28),
    startDateTime: DateTime(2026, 7, 28, 9, 7),
    duration: const Duration(minutes: 66),
  );

  test('shift drag snaps start to absolute quarter-hours', () {
    final result = anchor.applyDelta(
      const Offset(0, 15),
      config: config,
      mode: DragMode.shift,
      dayWidth: 100,
      heightPerMinute: 1,
    );

    expect(result.startDateTime, DateTime(2026, 7, 28, 9, 15));
    expect(result.duration, const Duration(minutes: 66));
  });

  test('resize drags snap the moved edge to absolute quarter-hours', () {
    final topResult = anchor.applyDelta(
      const Offset(0, 15),
      config: config,
      mode: DragMode.extendStart,
      dayWidth: 100,
      heightPerMinute: 1,
    );
    final bottomResult = anchor.applyDelta(
      const Offset(0, 15),
      config: config,
      mode: DragMode.extendEnd,
      dayWidth: 100,
      heightPerMinute: 1,
    );

    expect(topResult.startDateTime, DateTime(2026, 7, 28, 9, 15));
    expect(bottomResult.endDateTime, DateTime(2026, 7, 28, 10, 30));
  });

  test('resizing a projected edge materializes only that edge', () {
    final projected = anchor.copyWith(
      continuesBefore: true,
      continuesAfter: true,
    );

    final topResult = projected.applyDelta(
      const Offset(0, 15),
      config: config,
      mode: DragMode.extendStart,
      dayWidth: 100,
      heightPerMinute: 1,
    );
    final bottomResult = projected.applyDelta(
      const Offset(0, 15),
      config: config,
      mode: DragMode.extendEnd,
      dayWidth: 100,
      heightPerMinute: 1,
    );

    expect(topResult.continuesBefore, isFalse);
    expect(topResult.continuesAfter, isTrue);
    expect(bottomResult.continuesBefore, isTrue);
    expect(bottomResult.continuesAfter, isFalse);
  });
}
