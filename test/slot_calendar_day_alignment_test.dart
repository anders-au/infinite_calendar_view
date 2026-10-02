import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';
import 'package:infinite_calendar_view/src/utils/planner_time_mapper.dart';

void main() {
  // Run in a DST-observing local zone as well as UTC. These dates cross
  // Adelaide's October 4, 2026 transition, matching the reported failure.
  final initialDate = DateTime(2026, 10, 2);

  test('multi-day events retain every date when split across DST', () {
    for (final start in [DateTime(2026, 10, 3), DateTime(2026, 4, 4)]) {
      final end = DateTime(start.year, start.month, start.day + 3);
      final controller = EventsController();
      controller.calendarData.addEvents([
        Event(startTime: start, endTime: end, isFullDay: true),
      ]);
      for (var offset = 0; offset < 3; offset++) {
        final day = DateTime(start.year, start.month, start.day + offset);
        expect(controller.getFilteredDayEvents(day), hasLength(1));
      }
      expect(controller.getFilteredDayEvents(end), isNull);
    }
  });

  test('all-day factory spans the fall-back date once', () {
    final slot = CalendarSlot.allDayFromTap(
      columnIndex: 0,
      startDate: DateTime(2026, 4, 5),
      endDate: DateTime(2026, 4, 5),
    );
    expect(slot.startDateTime, DateTime(2026, 4, 5));
    expect(slot.endDateTime, DateTime(2026, 4, 6));
    expect(slot.totalDaysSpanned, 1);
  });

  test('all-day taps and moves retain midnight bounds across DST', () {
    final slot = CalendarSlot.allDayFromTap(
      columnIndex: 0,
      startDate: DateTime(2026, 10, 4),
      endDate: DateTime(2026, 10, 4),
    );
    expect(slot.endDateTime, DateTime(2026, 10, 5));
    expect(slot.totalDaysSpanned, 1);
    final shifted = slot.applyDelta(
      const Offset(100, 0),
      config: const SlotInteractionConfig(
        stepMinutes: 1440,
        enableVerticalAxis: false,
      ),
      mode: DragMode.shift,
      dayWidth: 100,
      heightPerMinute: 1,
    );
    expect(shifted.startDateTime, DateTime(2026, 10, 5));
    expect(shifted.endDateTime, DateTime(2026, 10, 6));
    expect(shifted.totalDaysSpanned, 1);
    expect(
      SlotConstraints.clamp(
        proposed: slot,
        anchor: slot,
        config: const SlotInteractionConfig(),
        mode: DragMode.extendEnd,
      ).endDateTime,
      DateTime(2026, 10, 5),
    );
  });

  test('timed horizontal drag keeps wall-clock hour across DST', () {
    final slot = CalendarSlot.fromTap(
      columnIndex: 0,
      startDateTime: DateTime(2026, 10, 3, 9),
    );
    final shifted = slot.applyDelta(
      const Offset(100, 0),
      config: const SlotInteractionConfig(),
      mode: DragMode.shift,
      dayWidth: 100,
      heightPerMinute: 1,
    );
    expect(shifted.startDateTime, DateTime(2026, 10, 4, 9));
    expect(shifted.endDateTime, DateTime(2026, 10, 4, 10));
    expect(shifted.toAllDay().endDateTime, DateTime(2026, 10, 5));
  });

  testWidgets('all-day and timed overlays use the same calendar column', (
    tester,
  ) async {
    final notifier = ValueNotifier<CalendarSlot?>(null);
    final rowNotifier = ValueNotifier<int?>(0);
    addTearDown(notifier.dispose);
    addTearDown(rowNotifier.dispose);
    for (final day in [5, 6, 7]) {
      for (final allDay in [true, false, true, false]) {
        final start = DateTime(2026, 10, day, allDay ? 0 : 9);
        notifier.value = CalendarSlot(
          columnIndex: 0,
          initialStartDate: start,
          startDateTime: start,
          duration: Duration(hours: allDay ? 24 : 8),
          isAllDay: allDay,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 700,
                height: 500,
                child: Stack(
                  children: [
                    if (allDay)
                      AllDaySlotOverlay(
                        slotNotifier: notifier,
                        rowNotifier: rowNotifier,
                        config: const SlotInteractionConfig(),
                        dayWidth: 100,
                        eventHeight: 30,
                        cellGapWidthPadding: 0,
                        eventEndGap: 0,
                        columnPositions: const [0, 100],
                        initialDate: initialDate,
                      )
                    else
                      SlotOverlay(
                        slotNotifier: notifier,
                        config: const SlotInteractionConfig(),
                        timeMapper: const PlannerTimeMapper(
                          heightPerMinute: 0.25,
                        ),
                        dayWidth: 100,
                        plannerHeight: 360,
                        dayTopPadding: 0,
                        dayBottomPadding: 0,
                        cellGapWidthPadding: 0,
                        columnPositions: const [0, 100],
                        initialDate: initialDate,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final positioned = tester.widgetList<Positioned>(
          find.descendant(
            of: find.byType(allDay ? AllDaySlotOverlay : SlotOverlay),
            matching: find.byType(Positioned),
          ),
        );
        expect(
          positioned.any((widget) => widget.left == (day - 2) * 100),
          isTrue,
          reason: 'October $day, allDay=$allDay must use its date column',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('day span includes every calendar date across DST', () {
    final start = DateTime(2026, 10, 3);
    final end = DateTime(2026, 10, 7);
    final slot = CalendarSlot(
      columnIndex: 0,
      initialStartDate: start,
      startDateTime: start,
      duration: end.difference(start),
      isAllDay: true,
    );
    expect(slot.totalDaysSpanned, 4);
    expect(
      CalendarDaySpanGeometry(
        start: start,
        end: end,
        dayWidth: 100,
        leadingPadding: 0,
        trailingGap: 0,
        endIsExclusive: true,
      ).naturalWidth,
      400,
    );
  });
}
