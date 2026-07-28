import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_calendar_view/src/controller/events_controller.dart';
import 'package:infinite_calendar_view/src/events/event.dart';
import 'package:infinite_calendar_view/src/events/side_events_arranger.dart';
import 'package:infinite_calendar_view/src/events_planner.dart';
import 'package:infinite_calendar_view/src/interactive_slot/slot_config.dart';
import 'package:infinite_calendar_view/src/interactive_slot/slot_selection.dart';
import 'package:infinite_calendar_view/src/painters/events_painters.dart';
import 'package:infinite_calendar_view/src/widgets/planner/day_widget.dart';
import 'package:infinite_calendar_view/src/widgets/planner/vertical_time_indicator_widget.dart';

void main() {
  testWidgets(
    'active slot excludes its backing event, dims overlaps, and gates taps',
    (tester) async {
      final day = DateTime(2026, 7, 28);
      final controller = EventsController();
      final builtEvents = <Object?>[];
      controller.calendarData.addEvents([
        Event(
          startTime: day.add(const Duration(hours: 8)),
          endTime: day.add(const Duration(hours: 9)),
          data: 'real',
        ),
        Event(
          startTime: day.add(const Duration(hours: 8, minutes: 15)),
          endTime: day.add(const Duration(hours: 8, minutes: 45)),
          data: 'interactive-backing-event',
        ),
      ]);
      controller.slotSelectionNotifier.value = CalendarSlot.fromTap(
        columnIndex: 0,
        startDateTime: day.add(const Duration(hours: 8, minutes: 15)),
        durationMinutes: 30,
      );
      expect(controller.getFilteredDayEvents(day), hasLength(2));

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: EventsListWidget(
              controller: controller,
              day: day,
              columIndex: 0,
              plannerHeight: 1440,
              heightPerMinute: 1,
              dayWidth: 200,
              dayEventsArranger: const SideEventArranger(),
              dayParam: DayParam(
                includeEventInTimedLayout: (event) =>
                    event.data != 'interactive-backing-event',
                slotInteractionConfig: const SlotInteractionConfig(
                  overlappingEventOpacity: 0.25,
                ),
                dayEventBuilder: (event, height, width, heightPerMinute) {
                  builtEvents.add(event.data);
                  return GestureDetector(
                    key: ValueKey<String>(event.data! as String),
                    onTap: () {},
                    child: ColoredBox(
                      color: Colors.blue,
                      child: SizedBox(width: width, height: height),
                    ),
                  );
                },
              ),
              showMultiDayEvents: true,
            ),
          ),
        ),
      );

      expect(builtEvents, ['real']);
      expect(find.byKey(const ValueKey<String>('real')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('interactive-backing-event')),
        findsNothing,
      );
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byKey(const ValueKey('real')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        0.25,
      );
      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(
                of: find.byKey(const ValueKey('real')),
                matching: find.byType(IgnorePointer),
              ),
            )
            .singleWhere((widget) => widget.child is Opacity)
            .ignoring,
        isTrue,
      );

      controller.slotSelectionNotifier.value = null;
      await tester.pump();

      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byKey(const ValueKey('real')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(
                of: find.byKey(const ValueKey('real')),
                matching: find.byType(IgnorePointer),
              ),
            )
            .singleWhere((widget) => widget.child is Opacity)
            .ignoring,
        isFalse,
      );
    },
  );

  testWidgets('slot time labels layer above a custom time-column painter', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 28);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          key: const ValueKey('time-column'),
          width: 60,
          height: 1440,
          child: VerticalTimeIndicatorWidget(
            timesIndicatorsParam: TimesIndicatorsParam(
              timesIndicatorsCustomPainter: (_) => _SlotAwareEmptyPainter(),
            ),
            heightPerMinute: 1,
            currentHourIndicatorHourVisibility: true,
            currentHourIndicatorColor: Colors.red,
            interactiveSlot: CalendarSlot.fromTap(
              columnIndex: 0,
              startDateTime: day.add(const Duration(hours: 7, minutes: 30)),
              durationMinutes: 60,
            ),
            slotInteractionConfig: const SlotInteractionConfig(
              use24HourFormat: false,
            ),
            floatingIndicatorTopInset: 10,
          ),
        ),
      ),
    );

    final customPaints = tester.widgetList<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('time-column')),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(
      customPaints.where(
        (paint) =>
            paint.foregroundPainter is HoursPainter &&
            !(paint.foregroundPainter! as HoursPainter).showRegularHours &&
            (paint.foregroundPainter! as HoursPainter)
                    .floatingIndicatorTopInset ==
                10,
      ),
      hasLength(1),
    );
    expect(
      (customPaints
                  .singleWhere(
                    (paint) =>
                        paint.foregroundPainter is _SlotAwareEmptyPainter,
                  )
                  .foregroundPainter
              as _SlotAwareEmptyPainter)
          .hiddenMinutes,
      [450, 510],
    );
  });
}

class _SlotAwareEmptyPainter extends CustomPainter
    implements SlotAwareTimeIndicatorPainter {
  _SlotAwareEmptyPainter({this.hiddenMinutes = const []});

  final List<int> hiddenMinutes;

  @override
  CustomPainter withHiddenTimeIndicatorMinutes(List<int> minutes) =>
      _SlotAwareEmptyPainter(hiddenMinutes: minutes);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_SlotAwareEmptyPainter oldDelegate) => false;
}
