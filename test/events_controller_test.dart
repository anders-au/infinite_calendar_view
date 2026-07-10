import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/events_controller.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/utils/extension.dart';

void main() {
  test('timed event crossing one midnight stays a single timed event', () {
    final controller = EventsController();
    final start = DateTime(2026, 7, 10, 23);
    final end = DateTime(2026, 7, 11, 1);
    final event = Event(startTime: start, endTime: end, title: 'Overnight');

    controller.calendarData.addEvents([event]);

    final firstDay = controller.calendarData.dayEvents[DateTime(2026, 7, 10)]!;
    final secondDay = controller.calendarData.dayEvents[DateTime(2026, 7, 11)]!;

    expect(firstDay, hasLength(1));
    expect(secondDay, hasLength(1));
    expect(firstDay.single.uniqueId, secondDay.single.uniqueId);
    expect(firstDay.single.isSingleMidnightCrossingTimedEvent, isTrue);
    expect(secondDay.single.isSingleMidnightCrossingTimedEvent, isTrue);
    expect(firstDay.single.timedStartMinuteInDay, 23 * 60);
    expect(firstDay.single.timedEndMinuteInDay, Event.minutesPerDay);
    expect(secondDay.single.timedStartMinuteInDay, 0);
    expect(secondDay.single.timedEndMinuteInDay, 60);
  });

  test(
    'timed event ending exactly at midnight has no zero-length next day',
    () {
      final controller = EventsController();
      final start = DateTime(2026, 7, 10, 22);
      final end = DateTime(2026, 7, 11);
      final event = Event(
        startTime: start,
        endTime: end,
        title: 'Until midnight',
      );

      controller.calendarData.addEvents([event]);

      final firstDay =
          controller.calendarData.dayEvents[DateTime(2026, 7, 10)]!;

      expect(firstDay, hasLength(1));
      expect(controller.calendarData.dayEvents[DateTime(2026, 7, 11)], isNull);
      expect(firstDay.single.isMultiDay, isFalse);
      expect(firstDay.single.timedStartMinuteInDay, 22 * 60);
      expect(firstDay.single.timedEndMinuteInDay, Event.minutesPerDay);
    },
  );

  test('single midnight timed segments can be selected for timed planner', () {
    final controller = EventsController();
    final start = DateTime(2026, 7, 10, 23);
    final end = DateTime(2026, 7, 11, 1);
    controller.calendarData.addEvents([
      Event(startTime: start, endTime: end, title: 'Overnight'),
    ]);

    final timedPlannerEvents = controller
        .getFilteredDayEvents(
          start.withoutTime,
          returnMultiDayEvents: true,
          returnFullDayEvent: false,
          returnMultiFullDayEvents: false,
        )!
        .where(
          (event) =>
              !event.isMultiDay || event.isSingleMidnightCrossingTimedEvent,
        )
        .toList();

    expect(timedPlannerEvents, hasLength(1));
    expect(
      timedPlannerEvents.single.isSingleMidnightCrossingTimedEvent,
      isTrue,
    );
  });
}
