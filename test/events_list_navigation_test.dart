import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

void main() {
  testWidgets('animateToDate snaps directly for far target days', (tester) async {
    final controller = EventsController()..focusedDay = DateTime(2026, 1, 10);
    final listViewController = EventsListViewController();
    final changedDays = <DateTime>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: EventsList(
              controller: controller,
              initialDate: DateTime(2026, 1, 10),
              listViewController: listViewController,
              onDayChange: changedDays.add,
              verticalScrollPhysics: const ClampingScrollPhysics(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final farAnimation = listViewController.animateToDate(
      DateTime(2026, 2, 10),
      duration: const Duration(milliseconds: 180),
    );
    await tester.pump();
    await farAnimation;

    expect(controller.focusedDay, DateTime(2026, 2, 10));
    expect(changedDays.last, DateTime(2026, 2, 10));
    expect(listViewController.isDateVisible(DateTime(2026, 2, 10)), isTrue);
  });
}
