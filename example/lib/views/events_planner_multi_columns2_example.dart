import 'package:example/app.dart';
import 'package:example/data.dart';
import 'package:example/utils.dart';
import 'package:example/views/widgets/avatar.dart';
import 'package:example/views/widgets/calendar.dart';
import 'package:example/views/widgets/event.dart';
import 'package:example/views/widgets/widget_utils.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

class PlannerMultiColumns2 extends StatefulWidget {
  const PlannerMultiColumns2({
    super.key,
  });

  @override
  State<PlannerMultiColumns2> createState() => _PlannerMultiColumns2State();
}

class _PlannerMultiColumns2State extends State<PlannerMultiColumns2> {
  GlobalKey<EventsPlannerState> oneDayViewKey = GlobalKey<EventsPlannerState>();
  late double heightPerMinute;
  late double initialVerticalScrollOffset;
  late DateTime selectedDay;
  var controller = EventsController()
    ..updateCalendarData((calendarData) {
      calendarData.addEvents(multiColumnEvents);
    });

  @override
  void initState() {
    super.initState();
    selectedDay = controller.focusedDay;
    heightPerMinute = 1.0;
    initialVerticalScrollOffset = heightPerMinute * 7 * 60;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 20),
        buildCalendar(),
        Divider(),
        Expanded(
          child: EventsPlanner(
            key: oneDayViewKey,
            controller: controller,
            daysShowed: 1,
            heightPerMinute: heightPerMinute,
            initialVerticalScrollOffset: initialVerticalScrollOffset,
            cellGapWidth: 10,

            // header
            daysHeaderParam: DaysHeaderParam(
              daysHeaderVisibility: false,
              daysHeaderHeight: 70,
              daysHeaderColor: Theme.of(context).colorScheme.surface,
            ),

            // custom column bar decoration
            fullDayParam: FullDayParam(
              fullDayEventsBarDecoration: Utils.customBarDecoration(context),
            ),

            // personalize columns
            columnsParam: ColumnsParam(
              columns: 7,
              maxColumns: 3,
              columnsWidthRatio: List.generate(7, (i) => 1 / 3),
              columnHeaderBuilder: (day, isToday, columIndex, columnWidth) {
                return Container(
                  width: columnWidth,
                  child: Avatar(columIndex: columIndex),
                );
              },
            ),

            // personalize offTimes per column
            offTimesParam: Utils.customOffTimes(context, isDarkMode),
            onDayChange: (newDay) => setState(() => selectedDay = newDay),

            // event cell
            dayParam: DayParam(
              dayEventBuilder: (event, height, width, heightPerMinute) =>
                  CustomEventWidgetExample(controller, event, height, width),
              onSlotTap: (columnIndex, exactDateTime, roundDateTime) =>
                  showSnack(context, "Slot Tap column = ${columnIndex}"),
              todayColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
      ],
    );
  }

  Calendar buildCalendar() {
    return Calendar(
      selectedDay: selectedDay,
      onDaySelected: (DateTime selectedDay, DateTime focusedDay) {
        setState(() {
          this.selectedDay = selectedDay;
        });
        controller.updateFocusedDay(selectedDay);
        oneDayViewKey.currentState?.jumpToDate(selectedDay);
      },
    );
  }
}
