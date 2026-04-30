import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/planner_view_controller.dart';

void main() {
  test('planner controller proxies calls when attached', () async {
    final controller = PlannerViewController();
    var dateAnimated = false;
    var dateJumped = false;
    var timeAnimated = false;
    var zoomSet = false;
    var nextPageAnimated = false;
    var todayVisibleChecked = false;

    controller.attach(
      animateToDate: (date, duration, curve) async {
        dateAnimated = true;
      },
      jumpToDate: (date) {
        dateJumped = true;
      },
      animateToNextPage: (duration, curve) async {
        nextPageAnimated = true;
      },
      animateToPreviousPage: (duration, curve) async {},
      jumpToNextPage: () {},
      jumpToPreviousPage: () {},
      animateToTime: (time, duration, curve) async {
        timeAnimated = true;
      },
      jumpToTime: (time) {},
      animateToZoom: (heightPerMinute, duration, curve) async {},
      jumpToZoom: (heightPerMinute) {
        zoomSet = true;
      },
      zoomGetter: () => 1.2,
      isDateVisible: (date) => date.year == 2026 && date.month == 1 && date.day == 1,
      isTodayVisible: () {
        todayVisibleChecked = true;
        return true;
      },
    );

    await controller.animateToDate(DateTime(2026, 1, 1));
    controller.jumpToDate(DateTime(2026, 1, 2));
    await controller.animateToTime(const TimeOfDay(hour: 9, minute: 0));
    await controller.nextPage();
    controller.setZoom(1.1);

    expect(dateAnimated, isTrue);
    expect(dateJumped, isTrue);
    expect(timeAnimated, isTrue);
    expect(nextPageAnimated, isTrue);
    expect(zoomSet, isTrue);
    expect(controller.currentHeightPerMinute, 1.2);
    expect(controller.isDateVisible(DateTime(2026, 1, 1)), isTrue);
    expect(controller.isDateVisible(DateTime(2026, 1, 2)), isFalse);
    expect(controller.isTodayVisible(), isTrue);
    expect(todayVisibleChecked, isTrue);
  });

  test('planner controller no-op when detached', () async {
    final controller = PlannerViewController();

    expect(controller.isAttached, isFalse);
    await controller.animateToDate(DateTime(2026, 1, 1));
    await controller.animateToNow();
    controller.jumpToNow();
    controller.setZoom(1.0);
    expect(controller.isDateVisible(DateTime(2026, 1, 1)), isFalse);
    expect(controller.isTodayVisible(), isFalse);
  });
}
