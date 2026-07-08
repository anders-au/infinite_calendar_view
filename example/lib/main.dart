import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

import 'app.dart';

class Example extends StatelessWidget {
  const Example({super.key, required this.eventsController});

  final EventsController eventsController;

  static final heightPerMinute = 1.0;
  static final initialVerticalScrollOffset = heightPerMinute * 7 * 60;

  @override
  Widget build(BuildContext context) {
    return EventsPlanner(
      controller: eventsController,
      daysShowed: 3,
      heightPerMinute: heightPerMinute,
      initialVerticalScrollOffset: initialVerticalScrollOffset,
      dayParam: DayParam(
        slotInteractionConfig: SlotInteractionConfig(
          enableLongPressSlotSelection: true,
        ),
      ),
    );
  }
}

void main() {
  runApp(App());
}
