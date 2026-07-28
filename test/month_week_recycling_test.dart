import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/events_controller.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/events_months.dart';
import 'package:infinite_calendar_view/src/widgets/month/week.dart';

void main() {
  testWidgets('reused week state reads events for its new dates', (
    tester,
  ) async {
    final controller = EventsController();
    controller.calendarData.addEvents([
      Event(
        startTime: DateTime(2026, 7, 7, 9),
        endTime: DateTime(2026, 7, 7, 10),
        title: 'Old Tuesday',
      ),
      Event(
        startTime: DateTime(2026, 7, 15, 9),
        endTime: DateTime(2026, 7, 15, 10),
        title: 'New Wednesday',
      ),
    ]);

    Future<void> pumpWeek(DateTime startOfWeek) {
      return tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 700,
            child: Week(
              controller: controller,
              textDirection: TextDirection.ltr,
              weekParam: const WeekParam(),
              weekHeight: 117,
              daysParam: const DaysParam(),
              startOfWeek: startOfWeek,
              maxEventsShowed: 3,
            ),
          ),
        ),
      );
    }

    await pumpWeek(DateTime(2026, 7, 5));
    expect(find.text('Old Tuesday'), findsOneWidget);
    expect(find.text('New Wednesday'), findsNothing);

    // Keep the same widget type and position, as a virtualized month list does
    // when it recycles a week state for a different date range.
    await pumpWeek(DateTime(2026, 7, 12));
    expect(find.text('Old Tuesday'), findsNothing);
    expect(find.text('New Wednesday'), findsOneWidget);
  });
}
