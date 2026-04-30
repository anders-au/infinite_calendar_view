import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/months_view_controller.dart';

void main() {
  test('months controller proxies calls when attached', () async {
    final controller = MonthsViewController();
    var dateAnimated = false;
    var nextPageAnimated = false;
    var zoomSet = false;
    var todayVisibleChecked = false;

    controller.attach(
      animateToDate: (date, duration, curve) async {
        dateAnimated = true;
      },
      jumpToDate: (date) {},
      animateToNextPage: (duration, curve) async {
        nextPageAnimated = true;
      },
      animateToPreviousPage: (duration, curve) async {},
      jumpToNextPage: () {},
      jumpToPreviousPage: () {},
      animateToZoom: (weekHeight, duration, curve) async {},
      jumpToZoom: (weekHeight) {
        zoomSet = true;
      },
      zoomGetter: () => 120,
      isDateVisible: (date) => date.year == 2026 && date.month == 1,
      isTodayVisible: () {
        todayVisibleChecked = true;
        return true;
      },
    );

    await controller.animateToDate(DateTime(2026, 1, 1));
    await controller.nextPage();
    controller.setZoom(130);

    expect(dateAnimated, isTrue);
    expect(nextPageAnimated, isTrue);
    expect(zoomSet, isTrue);
    expect(controller.currentWeekHeight, 120);
    expect(controller.isDateVisible(DateTime(2026, 1, 15)), isTrue);
    expect(controller.isDateVisible(DateTime(2026, 2, 1)), isFalse);
    expect(controller.isTodayVisible(), isTrue);
    expect(todayVisibleChecked, isTrue);
  });

  test('months controller no-op when detached', () async {
    final controller = MonthsViewController();

    expect(controller.isAttached, isFalse);
    await controller.animateToDate(DateTime(2026, 1, 1));
    await controller.nextPage();
    controller.jumpToDate(DateTime(2026, 1, 1));
    controller.setZoom(117);
    expect(controller.isDateVisible(DateTime(2026, 1, 1)), isFalse);
    expect(controller.isTodayVisible(), isFalse);
  });
}
