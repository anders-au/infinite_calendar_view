import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/events_controller.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/events_list.dart';

void main() {
  testWidgets(
    'loading a sparse day keeps the active scroll controller attached',
    (tester) async {
      final day = DateTime(2026, 9, 14);
      final eventsController = EventsController();
      final scrollController = ScrollController();
      eventsController.calendarData.addEvents([
        Event(startTime: day, endTime: day.add(const Duration(hours: 1))),
        for (var offset = 3; offset < 12; offset++)
          Event(
            startTime: day.add(Duration(days: offset)),
            endTime: day.add(Duration(days: offset, hours: 1)),
          ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 240,
            child: EventsList(
              controller: eventsController,
              initialDate: day,
              verticalController: scrollController,
              hideDaysWithoutEvents: true,
              dayEventsBuilder: (day, events) => SizedBox(
                height: 160,
                child: Text('${day.day}:${events?.length ?? 0}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollPosition = scrollController.position;
      await tester.fling(find.text('14:1'), const Offset(0, -180), 1000);
      await tester.pump();
      expect(scrollPosition.isScrollingNotifier.value, isTrue);

      eventsController.calendarData.addEvents([
        Event(
          startTime: day.add(const Duration(days: 1)),
          endTime: day.add(const Duration(days: 1, hours: 1)),
        ),
      ]);
      eventsController.notifyListeners();
      await tester.pump();

      expect(scrollController.hasClients, isTrue);
      expect(scrollPosition.isScrollingNotifier.value, isTrue);
    },
  );
}
