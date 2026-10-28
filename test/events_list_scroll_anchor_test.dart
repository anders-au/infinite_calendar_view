import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

DateTime day(int offset) => DateTime(2026, 6, 1 + offset);
Event event(int offset) => Event(
  startTime: day(offset),
  endTime: day(offset).add(const Duration(hours: 1)),
  title: 'event-$offset',
);

Future<void> mount(
  WidgetTester tester,
  EventsController events,
  ScrollController scroll, {
  ValueChanged<DateTime>? onDayChange,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: EventsList(
              controller: events,
              initialDate: day(0),
              maxPreviousDays: null,
              maxNextDays: null,
              verticalController: scroll,
              hideDaysWithoutEvents: true,
              verticalScrollPhysics: const ClampingScrollPhysics(),
              onDayChange: onDayChange,
              dayHeaderBuilder: (_, _, _) => const SizedBox.shrink(),
              dayEventsBuilder: (date, data) => SizedBox(
                key: ValueKey('row-${date.toIso8601String()}'),
                height: 100 + (date.day % 3) * 35,
                child: Text('${date.day}:${data?.single.title}'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder row(DateTime date) =>
    find.byKey(ValueKey('row-${date.toIso8601String()}'));
DateTime firstVisible(WidgetTester tester) {
  for (var i = -30; i < 60; i++) {
    final finder = row(day(i));
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder);
    if (rect.bottom > 0 && rect.top < 300) return day(i);
  }
  throw StateError('No visible day');
}

void main() {
  testWidgets(
    'range eviction can remove index zero without moving the viewport',
    (tester) async {
      final events = EventsController();
      final scroll = ScrollController();
      events.calendarData.addEvents([
        for (var i = -20; i < 40; i += 2) event(i),
      ]);
      await mount(tester, events, scroll);
      scroll.jumpTo(1200);
      await tester.pumpAndSettle();
      final anchor = firstVisible(tester);
      final y = tester.getTopLeft(row(anchor)).dy;
      events.updateCalendarData((data) {
        data.clearAll();
        data.addEvents([for (var i = 10; i < 60; i += 2) event(i)]);
      });
      await tester.pumpAndSettle();
      expect(firstVisible(tester), anchor);
      expect(tester.getTopLeft(row(anchor)).dy, closeTo(y, 1));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      events.dispose();
    },
  );

  testWidgets('sparse date jumps reset the origin after an anchored update', (
    tester,
  ) async {
    final events = EventsController();
    final scroll = ScrollController();
    events.calendarData.addEvents([for (var i = -20; i < 40; i += 2) event(i)]);
    await mount(tester, events, scroll);
    scroll.jumpTo(425);
    await tester.pumpAndSettle();
    events.updateCalendarData((data) => data.addEvents([event(-19)]));
    await tester.pumpAndSettle();
    final state = tester.state<EventsListState>(find.byType(EventsList));
    state.jumpToDate(day(20));
    await tester.pumpAndSettle();
    expect(firstVisible(tester), day(20));
    expect(tester.getTopLeft(row(day(20))).dy, closeTo(0, 1));
    expect(events.focusedDay, day(20));
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    events.dispose();
  });

  for (final backwards in [false, true]) {
    testWidgets(
      'preserves visible date and pixels scrolling ${backwards ? "backward" : "forward"}',
      (tester) async {
        final events = EventsController();
        final scroll = ScrollController();
        events.calendarData.addEvents([
          for (var i = -20; i < 40; i += 2) event(i),
        ]);
        final changes = <DateTime>[];
        await mount(tester, events, scroll, onDayChange: changes.add);
        scroll.jumpTo(backwards ? -425 : 425);
        await tester.pumpAndSettle();
        final position = scroll.position;
        final anchor = firstVisible(tester);
        final y = tester.getTopLeft(row(anchor)).dy;
        events.updateCalendarData((data) {
          data.addEvents([event(-19), event(1)]);
          data.removeDayEvents(day(-18));
        });
        await tester.pumpAndSettle();
        expect(scroll.position, same(position));
        expect(firstVisible(tester), anchor);
        expect(tester.getTopLeft(row(anchor)).dy, closeTo(y, 1));
        expect(changes.last, anchor);
        expect(events.focusedDay, anchor);
        expect(
          find.text('${anchor.day}:event-${anchor.difference(day(0)).inDays}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
        events.dispose();
      },
    );
  }

  for (final backwards in [false, true]) {
    testWidgets(
      'keeps a ${backwards ? "backward" : "forward"} fling moving while replacing a loaded range',
      (tester) async {
        final events = EventsController();
        final scroll = ScrollController();
        events.calendarData.addEvents([
          for (var i = -20; i < 40; i += 2) event(i),
        ]);
        await mount(tester, events, scroll);
        await tester.fling(
          find.byType(EventsList),
          Offset(0, backwards ? 430 : -430),
          1200,
        );
        await tester.pump();
        final position = scroll.position;
        final anchor = firstVisible(tester);
        final y = tester.getTopLeft(row(anchor)).dy;
        events.updateCalendarData((data) {
          data.clearAll();
          data.addEvents([for (var i = -10; i < 60; i += 2) event(i)]);
        });
        await tester.pump();
        expect(scroll.position, same(position));
        expect(position.isScrollingNotifier.value, isTrue);
        expect(tester.getTopLeft(row(anchor)).dy, closeTo(y, 1));
        await tester.pump(const Duration(milliseconds: 40));
        expect(
          tester.getTopLeft(row(anchor)).dy,
          backwards ? greaterThan(y) : lessThan(y),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
        events.dispose();
      },
    );
  }

  testWidgets('coalesces updates and handles removed anchors and empty lists', (
    tester,
  ) async {
    final events = EventsController();
    final scroll = ScrollController();
    final changes = <DateTime>[];
    events.calendarData.addEvents([for (var i = -20; i < 40; i += 2) event(i)]);
    await mount(tester, events, scroll, onDayChange: changes.add);
    scroll.jumpTo(425);
    await tester.pumpAndSettle();
    final anchor = firstVisible(tester);
    final y = tester.getTopLeft(row(anchor)).dy;
    events.updateCalendarData((data) => data.addEvents([event(-19)]));
    events.updateCalendarData((data) => data.addEvents([event(-17)]));
    await tester.pumpAndSettle();
    expect(firstVisible(tester), anchor);
    expect(tester.getTopLeft(row(anchor)).dy, closeTo(y, 1));
    final nextDay = DateTime(anchor.year, anchor.month, anchor.day + 2);
    final nextY = tester.getTopLeft(row(nextDay)).dy;
    events.updateCalendarData((data) => data.removeDayEvents(anchor));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(row(nextDay)).dy, closeTo(nextY, 1));
    expect(
      find.textContaining('event-${anchor.difference(day(0)).inDays}'),
      findsNothing,
    );
    events.updateCalendarData((data) => data.clearAll());
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
    events.updateCalendarData(
      (data) => data.addEvents([event(12), event(14), event(16)]),
    );
    await tester.pumpAndSettle();
    expect(firstVisible(tester), day(12));
    expect(events.focusedDay, day(12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    events.dispose();
  });
}
