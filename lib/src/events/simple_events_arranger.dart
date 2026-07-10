import 'event.dart';
import 'event_arranger.dart';

class SimpleEventArranger extends EventArranger {
  const SimpleEventArranger({this.paddingLeft = 0, this.paddingRight = 0});

  final double paddingLeft;
  final double paddingRight;

  @override
  List<OrganizedEvent> arrange({
    required List<Event> events,
    required double height,
    required double width,
    required double heightPerMinute,
  }) {
    var organizedEvents = events
        .map(
          (event) => OrganizedEvent(
            top: event.timedStartMinuteInDay * heightPerMinute,
            bottom: height - (event.timedEndMinuteInDay * heightPerMinute),
            left: paddingLeft,
            right: paddingRight,
            startDuration: event.startTime,
            endDuration: event.endTime!,
            event: event,
          ),
        )
        .toList();
    return organizedEvents;
  }
}
