import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

void main() {
  test(
    'DaySnappingScrollPhysics keeps gentle flings on the nearest visible page',
    () {
      const physics = DaySnappingScrollPhysics(
        pageSize: 100,
        parent: ClampingScrollPhysics(),
      );
      final metrics = FixedScrollMetrics(
        minScrollExtent: -1000,
        maxScrollExtent: 1000,
        pixels: 40,
        viewportDimension: 300,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1,
      );

      final simulation = physics.createBallisticSimulation(metrics, 500)!;

      expect(simulation.x(10), moreOrLessEquals(0, epsilon: 0.01));
    },
  );

  test('DaySnappingScrollPhysics lets deliberate flings advance pages', () {
    const physics = DaySnappingScrollPhysics(
      pageSize: 100,
      parent: ClampingScrollPhysics(),
    );
    final metrics = FixedScrollMetrics(
      minScrollExtent: -1000,
      maxScrollExtent: 1000,
      pixels: 40,
      viewportDimension: 300,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1,
    );

    final simulation = physics.createBallisticSimulation(metrics, 700)!;

    expect(simulation.x(10), moreOrLessEquals(100, epsilon: 0.01));
  });

  testWidgets('animateToDate preserves the current 3-day bracket alignment', (
    tester,
  ) async {
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
