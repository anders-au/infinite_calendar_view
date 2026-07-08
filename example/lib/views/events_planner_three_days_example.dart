import 'package:example/app.dart';
import 'package:example/utils.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';
import 'package:intl/intl.dart';

class PlannerTreeDays extends StatelessWidget {
  const PlannerTreeDays({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var heightPerMinute = 1.0;
    var initialVerticalScrollOffset = heightPerMinute * 7 * 60;

    return EventsPlanner(
      controller: eventsController,
      daysShowed: 3,
      heightPerMinute: heightPerMinute,
      initialVerticalScrollOffset: initialVerticalScrollOffset,
      daysHeaderParam: DaysHeaderParam(
        daysHeaderVisibility: true,
        dayHeaderTextBuilder: (day) => DateFormat("E d").format(day),
      ),
      dayParam: DayParam(
        onSlotMinutesRound: 60,
        onSlotRoundAlwaysBefore: true,
        slotInteractionConfig: SlotInteractionConfig(
          enableTapSlotSelection: true,
          enableLongPressSlotSelection: true,
          onTap: (slot) => showSnack(
            context,
            "${slot.startDateTime} : ${slot.durationInMinutes}",
          ),
        ),
      ),
    );
  }
}
