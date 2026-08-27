import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

void main() {
  testWidgets('all-day row count shrinks as soon as event leaves viewport', (
    tester,
  ) async {
    final eventsController = EventsController();
    final scrollController = ScrollController();
    final maxRows = ValueNotifier<int>(0);
    final initialDate = DateTime(2026, 7, 1);

    eventsController.updateCalendarData(
      (data) => data.addEvents([
        Event(
          startTime: initialDate,
          endTime: DateTime(2026, 7, 3, 23, 59),
          isFullDay: true,
        ),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 80,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 1000, height: 1),
                ),
                Positioned.fill(
                  child: MultiDayEventsOverlay(
                    controller: eventsController,
                    scrollController: scrollController,
                    fullDayParam: const FullDayParam(),
                    dayWidth: 100,
                    cellGapWidthPadding: 0,
                    getDayFromIndex: (index) =>
                        initialDate.add(Duration(days: index)),
                    maxRowsNotifier: maxRows,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(maxRows.value, 1);

    scrollController.jumpTo(301);
    await tester.pump();

    expect(maxRows.value, 0);

    maxRows.dispose();
    scrollController.dispose();
    eventsController.dispose();
  });

  testWidgets('all-day slot geometry follows horizontal scroll continuously', (
    tester,
  ) async {
    final scrollController = ScrollController();
    final slotNotifier = ValueNotifier<CalendarSlot?>(
      CalendarSlot(
        columnIndex: 0,
        initialStartDate: DateTime(2026, 7, 1),
        startDateTime: DateTime(2026, 7, 1),
        duration: const Duration(days: 5),
        isAllDay: true,
        continuesBefore: true,
        continuesAfter: true,
      ),
    );
    final rowNotifier = ValueNotifier<int?>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 80,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 1000, height: 1),
                ),
                AllDaySlotOverlay(
                  slotNotifier: slotNotifier,
                  config: const SlotInteractionConfig(),
                  dayWidth: 100,
                  eventHeight: 40,
                  cellGapWidthPadding: 0,
                  eventEndGap: 0,
                  columnPositions: const [0, 100],
                  initialDate: DateTime(2026, 7, 1),
                  mainContentScrollController: scrollController,
                  viewportWidth: 300,
                  rowNotifier: rowNotifier,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    double shiftWidth() => tester
        .widget<Positioned>(
          find.byKey(const ValueKey('allDaySlot.shift.positioned')),
        )
        .width!;

    final initialWidth = shiftWidth();
    scrollController.jumpTo(25);
    await tester.pump();
    final partialWidth = shiftWidth();
    scrollController.jumpTo(50);
    await tester.pump();
    final laterWidth = shiftWidth();

    expect(partialWidth, isNot(initialWidth));
    expect(laterWidth, lessThan(partialWidth));

    rowNotifier.dispose();
    slotNotifier.dispose();
    scrollController.dispose();
  });

  testWidgets('long press on multi-day event selects the pressed day', (
    tester,
  ) async {
    final eventsController = EventsController();
    final scrollController = ScrollController();
    final initialDate = DateTime(2026, 7, 1);

    eventsController.updateCalendarData(
      (data) => data.addEvents([
        Event(
          startTime: initialDate,
          endTime: DateTime(2026, 7, 3, 23, 59),
          isFullDay: true,
        ),
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 80,
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 1000, height: 1),
                ),
                Positioned.fill(
                  child: MultiDayEventsOverlay(
                    controller: eventsController,
                    scrollController: scrollController,
                    fullDayParam: const FullDayParam(),
                    dayWidth: 100,
                    cellGapWidthPadding: 0,
                    getDayFromIndex: (index) =>
                        initialDate.add(Duration(days: index)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.longPressAt(const Offset(150, 12));
    await tester.pump();

    expect(
      eventsController.slotSelectionNotifier.value?.startDateTime,
      DateTime(2026, 7, 2),
    );

    scrollController.dispose();
    eventsController.dispose();
  });

  testWidgets(
    'visible all-day events repack when a middle event leaves viewport',
    (tester) async {
      final eventsController = EventsController();
      final scrollController = ScrollController();
      final maxRows = ValueNotifier<int>(0);
      final initialDate = DateTime(2026, 7, 1);

      eventsController.updateCalendarData(
        (data) => data.addEvents([
          Event(
            startTime: initialDate,
            endTime: DateTime(2026, 7, 6, 23, 59),
            isFullDay: true,
          ),
          Event(
            startTime: DateTime(2026, 7, 2),
            endTime: DateTime(2026, 7, 4, 23, 59),
            isFullDay: true,
          ),
          Event(
            startTime: DateTime(2026, 7, 3),
            endTime: DateTime(2026, 7, 6, 23, 59),
            isFullDay: true,
          ),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 120,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: const SizedBox(width: 1000, height: 1),
                  ),
                  Positioned.fill(
                    child: MultiDayEventsOverlay(
                      controller: eventsController,
                      scrollController: scrollController,
                      fullDayParam: const FullDayParam(),
                      dayWidth: 100,
                      cellGapWidthPadding: 0,
                      getDayFromIndex: (index) =>
                          initialDate.add(Duration(days: index)),
                      maxRowsNotifier: maxRows,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      scrollController.jumpTo(200);
      await tester.pump();
      expect(maxRows.value, 3);

      scrollController.jumpTo(401);
      await tester.pump();
      expect(maxRows.value, 2);

      maxRows.dispose();
      scrollController.dispose();
      eventsController.dispose();
    },
  );
}
