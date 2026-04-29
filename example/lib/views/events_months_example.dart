import 'package:example/app.dart';
import 'package:flutter/material.dart';
import 'package:infinite_calendar_view/infinite_calendar_view.dart';

class Months extends StatefulWidget {
  const Months({
    super.key,
  });

  @override
  State<Months> createState() => _MonthsState();
}

class _MonthsState extends State<Months> {
  final MonthsViewController monthsViewController = MonthsViewController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => monthsViewController.previousPage(),
            ),
            IconButton(
              icon: const Icon(Icons.today),
              onPressed: () => monthsViewController.animateToDate(DateTime.now()),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => monthsViewController.nextPage(),
            ),
          ],
        ),
        Expanded(
          child: EventsMonths(
            controller: eventsController,
            monthsViewController: monthsViewController,
            daysParam: DaysParam(
              // custom builder : add drag and drop
              dayEventBuilder: (event, width, height) {
                return DraggableMonthEvent(
                  child: DefaultMonthDayEvent(event: event),
                  onDragEnd: (DateTime day) {
                    eventsController.updateCalendarData((data) => move(data, event, day));
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  move(CalendarData data, Event event, DateTime newDay) {
    data.moveEvent(
      event,
      newDay.copyWith(
        hour: event.effectiveStartTime!.hour,
        minute: event.effectiveStartTime!.minute,
      ),
    );
  }
}
