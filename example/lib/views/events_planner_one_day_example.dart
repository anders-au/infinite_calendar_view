import 'package:example/app.dart';
import 'package:example/views/widgets/calendar.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';
import 'package:intl/intl.dart';

class PlannerOneDay extends StatefulWidget {
  const PlannerOneDay({
    super.key,
  });

  @override
  State<PlannerOneDay> createState() => _PlannerOneDayState();
}

class _PlannerOneDayState extends State<PlannerOneDay> {
  final PlannerViewController plannerViewController = PlannerViewController();
  late DateTime selectedDay;

  @override
  void initState() {
    super.initState();
    selectedDay = eventsController.focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    var heightPerMinute = 1.0;
    var initialVerticalScrollOffset = heightPerMinute * 7 * 60;

    return Column(
      children: [
        const SizedBox(height: 8.0),
        buildCalendar(),
        const SizedBox(height: 4.0),
        Divider(
          color: Theme.of(context).colorScheme.outlineVariant,
          height: 2,
        ),
        Expanded(
          child: EventsPlanner(
            controller: eventsController,
            plannerViewController: plannerViewController,
            daysShowed: 1,
            heightPerMinute: heightPerMinute,
            initialVerticalScrollOffset: initialVerticalScrollOffset,
            horizontalScrollPhysics: const PageScrollPhysics(),
            daysHeaderParam: DaysHeaderParam(
              daysHeaderVisibility: false,
              dayHeaderTextBuilder: (day) => DateFormat("E d").format(day),
            ),
            onDayChange: (firstDay) {
              setState(() {
                selectedDay = firstDay;
              });
            },
            dayParam: DayParam(
              dayEventBuilder: (event, height, width, heightPerMinute) {
                return DefaultDayEvent(
                  height: height,
                  width: width,
                  title: event.title,
                  description: event.description,
                  color: event.color,
                  textColor: event.textColor,
                  roundBorderRadius: 15,
                  horizontalPadding: 8,
                  verticalPadding: 4,
                  onTap: () => print("tap ${event.uniqueId}"),
                  onTapDown: (details) => print("tapdown ${event.uniqueId}"),
                );
              },
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
        eventsController.updateFocusedDay(selectedDay);
        plannerViewController.jumpToDate(selectedDay);
      },
    );
  }
}
