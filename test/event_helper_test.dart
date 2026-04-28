import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/utils/event_helper.dart';

void main() {
  Event createMultiDaySegment({
    required Event root,
    required DateTime day,
    required int dayIndex,
  }) {
    return root.copyWith(
      startTime: day,
      endTime: day.add(const Duration(days: 1)),
      daysIndex: dayIndex,
      effectiveEndTime: root.endTime,
    );
  }

  test(
    'getWeekMultiDaysEventsSortedMap keeps distinct multi-day events with same start',
    () {
      final weekStart = DateTime(2026, 4, 6);

      final eventARoot = Event(
        startTime: weekStart,
        endTime: weekStart.add(const Duration(days: 2)),
        isFullDay: true,
        title: 'A',
        columnIndex: 0,
        daysIndex: 0,
      )..effectiveEndTime = weekStart.add(const Duration(days: 2));

      final eventBRoot = Event(
        startTime: weekStart,
        endTime: weekStart.add(const Duration(days: 2)),
        isFullDay: true,
        title: 'B',
        columnIndex: 1,
        daysIndex: 0,
      )..effectiveEndTime = weekStart.add(const Duration(days: 2));

      final weekEvents = List<List<Event>?>.filled(7, null, growable: false);
      weekEvents[0] = [
        createMultiDaySegment(root: eventARoot, day: weekStart, dayIndex: 0),
        createMultiDaySegment(root: eventBRoot, day: weekStart, dayIndex: 0),
      ];
      weekEvents[1] = [
        createMultiDaySegment(
          root: eventARoot,
          day: weekStart.add(const Duration(days: 1)),
          dayIndex: 1,
        ),
        createMultiDaySegment(
          root: eventBRoot,
          day: weekStart.add(const Duration(days: 1)),
          dayIndex: 1,
        ),
      ];
      weekEvents[2] = [
        createMultiDaySegment(
          root: eventARoot,
          day: weekStart.add(const Duration(days: 2)),
          dayIndex: 2,
        ),
        createMultiDaySegment(
          root: eventBRoot,
          day: weekStart.add(const Duration(days: 2)),
          dayIndex: 2,
        ),
      ];

      final firstSorted = getWeekMultiDaysEventsSortedMap(weekEvents);
      final secondSorted = getWeekMultiDaysEventsSortedMap(weekEvents);

      expect(firstSorted.length, 2);
      expect(secondSorted.length, 2);
      expect(firstSorted.keys.toList(), orderedEquals(secondSorted.keys.toList()));

      for (final eventMap in firstSorted.values) {
        expect(eventMap.length, 3);
      }

      final shown = getShowedWeekEvents(weekEvents, 4);

      for (var day = 0; day <= 2; day++) {
        final visibleMultiDayIds = shown[day]
            .whereType<Event>()
            .where((e) => e.isMultiDay)
            .map((e) => e.uniqueId)
            .toSet();
        expect(visibleMultiDayIds.length, 2);
        expect(visibleMultiDayIds.contains(eventARoot.uniqueId), isTrue);
        expect(visibleMultiDayIds.contains(eventBRoot.uniqueId), isTrue);
      }
    },
  );
}
