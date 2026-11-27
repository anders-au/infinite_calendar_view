import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';
import 'package:infinite_calendar_view/src/utils/planner_time_mapper.dart';

void main() {
  group('timed slot resize handles', () {
    // One pixel per minute: the 10:00–11:00 slot spans y 600–660 in a
    // 100px column at x 0–100.
    Future<List<DragMode>> pumpTimedSlot(
      WidgetTester tester, {
      required double handleOutsideExtent,
    }) async {
      tester.view.physicalSize = const Size(300, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final started = <DragMode>[];
      final slotNotifier = ValueNotifier<CalendarSlot?>(
        CalendarSlot(
          columnIndex: 0,
          initialStartDate: DateTime(2026, 7, 1, 10),
          startDateTime: DateTime(2026, 7, 1, 10),
          duration: const Duration(hours: 1),
        ),
      );
      addTearDown(slotNotifier.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              SlotOverlay(
                slotNotifier: slotNotifier,
                config: SlotInteractionConfig(
                  handleOutsideExtent: handleOutsideExtent,
                  onDragStart: started.add,
                ),
                timeMapper: const PlannerTimeMapper(heightPerMinute: 1),
                dayWidth: 100,
                plannerHeight: 1440,
                dayTopPadding: 0,
                dayBottomPadding: 0,
                cellGapWidthPadding: 0,
                columnPositions: const [0, 100],
                initialDate: DateTime(2026, 7, 1),
                onChanged: (slot) => slotNotifier.value = slot,
              ),
            ],
          ),
        ),
      );
      return started;
    }

    testWidgets('a press just above the slot resizes its start', (
      tester,
    ) async {
      final started = await pumpTimedSlot(tester, handleOutsideExtent: 16);

      await tester.dragFrom(const Offset(50, 590), const Offset(0, -30));
      await tester.pumpAndSettle();

      expect(started, [DragMode.extendStart]);
    });

    testWidgets('a press just below the slot resizes its end', (tester) async {
      final started = await pumpTimedSlot(tester, handleOutsideExtent: 16);

      await tester.dragFrom(const Offset(50, 670), const Offset(0, 30));
      await tester.pumpAndSettle();

      expect(started, [DragMode.extendEnd]);
    });

    testWidgets('a zero extent keeps the zones inside the slot', (
      tester,
    ) async {
      final started = await pumpTimedSlot(tester, handleOutsideExtent: 0);

      await tester.dragFrom(const Offset(50, 590), const Offset(0, -30));
      await tester.dragFrom(const Offset(50, 670), const Offset(0, 30));
      await tester.pumpAndSettle();

      expect(started, isEmpty);
    });
  });

  group('all-day slot resize handles', () {
    // The one-day slot on 2 July spans x 100–200 and y 2–42.
    Future<List<DragMode>> pumpAllDaySlot(WidgetTester tester) async {
      final started = <DragMode>[];
      final rowNotifier = ValueNotifier<int?>(0);
      final slotNotifier = ValueNotifier<CalendarSlot?>(
        CalendarSlot(
          columnIndex: 0,
          initialStartDate: DateTime(2026, 7, 2),
          startDateTime: DateTime(2026, 7, 2),
          duration: const Duration(days: 1),
          isAllDay: true,
        ),
      );
      addTearDown(rowNotifier.dispose);
      addTearDown(slotNotifier.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 80,
              child: Stack(
                children: [
                  AllDaySlotOverlay(
                    slotNotifier: slotNotifier,
                    config: SlotInteractionConfig(onDragStart: started.add),
                    dayWidth: 100,
                    eventHeight: 40,
                    cellGapWidthPadding: 0,
                    eventEndGap: 0,
                    columnPositions: const [0, 100],
                    initialDate: DateTime(2026, 7, 1),
                    viewportWidth: 300,
                    rowNotifier: rowNotifier,
                    onChanged: (slot) => slotNotifier.value = slot,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return started;
    }

    testWidgets('a press just left of the slot resizes its start', (
      tester,
    ) async {
      final started = await pumpAllDaySlot(tester);

      await tester.dragFrom(const Offset(92, 20), const Offset(-40, 0));
      await tester.pumpAndSettle();

      expect(started, [DragMode.extendStart]);
    });

    testWidgets('a press just right of the slot resizes its end', (
      tester,
    ) async {
      final started = await pumpAllDaySlot(tester);

      await tester.dragFrom(const Offset(208, 20), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(started, [DragMode.extendEnd]);
    });
  });
}
