import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

void main() {
  testWidgets('animateToDate preserves the current 3-day bracket alignment', (tester) async {
    final controller = EventsController()..focusedDay = DateTime(2026, 1, 10);
    final plannerViewController = PlannerViewController();
    final changedDays = <DateTime>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: EventsPlanner(
              controller: controller,
              initialDate: DateTime(2026, 1, 10),
              daysShowed: 3,
              plannerViewController: plannerViewController,
              onDayChange: changedDays.add,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await plannerViewController.animateToDate(
      DateTime(2026, 1, 15),
      duration: const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();

    expect(changedDays.last, DateTime(2026, 1, 13));
    expect(controller.focusedDay, DateTime(2026, 1, 13));
  });
}
