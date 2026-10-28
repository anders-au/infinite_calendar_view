import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

class _TrackedEventsController extends EventsController {
  bool get isObserved => hasListeners;
}

void main() {
  testWidgets(
    'reused day and header refresh dates and move controller listeners',
    (tester) async {
      final a = DateTime(2026, 3, 11);
      final b = DateTime(2026, 6, 11);
      final first = _TrackedEventsController();
      final second = _TrackedEventsController();
      Event event(DateTime day, String title) => Event(
        startTime: day,
        endTime: day.add(const Duration(hours: 1)),
        title: title,
      );
      first.calendarData.addEvents([event(a, 'March'), event(b, 'June')]);
      second.calendarData.addEvents([event(b, 'replacement')]);

      Future<void> show(EventsController controller, DateTime day) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                DayEvents(
                  controller: controller,
                  day: day,
                  dayEventsBuilder: (date, events) =>
                      Text('body-${date.month}:${events?.single.title}'),
                ),
                HeaderListWidget(
                  controller: controller,
                  day: day,
                  isToday: false,
                  dayHeaderBuilder: (date, _, events) =>
                      Text('header-${date.month}:${events?.single.title}'),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
      }

      await show(first, a);
      expect(find.text('body-3:March'), findsOneWidget);
      expect(find.text('header-3:March'), findsOneWidget);
      await show(first, b);
      expect(find.text('body-6:June'), findsOneWidget);
      expect(find.text('header-6:June'), findsOneWidget);
      await show(second, b);
      expect(find.text('body-6:replacement'), findsOneWidget);
      expect(find.text('header-6:replacement'), findsOneWidget);
      expect(first.isObserved, isFalse);
      first.notifyListeners();
      second.updateCalendarData(
        (data) => data.replaceDayEvents(b, [event(b, 'updated')]),
      );
      await tester.pump();
      expect(find.text('body-6:updated'), findsOneWidget);
      expect(find.text('header-6:updated'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(second.isObserved, isFalse);
      first.dispose();
      second.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
