import 'event.dart';
import 'event_arranger.dart';

class SideEventArranger extends EventArranger {
  const SideEventArranger({this.paddingLeft = 0, this.paddingRight = 0});

  final double paddingLeft;
  final double paddingRight;

  @override
  List<OrganizedEvent> arrange({
    required List<Event> events,
    required double height,
    required double width,
    required double heightPerMinute,
  }) {
    var eventsConflict = <Event, List<Event>>{};
    var eventsConflictGroup = <Event, Set<Event>>{};

    // determine conflict to each event
    for (var event in events) {
      var conflicts = events
          .where(
            (e) =>
                e != event &&
                e.startTime.isBefore(event.endTime!) == true &&
                e.endTime!.isAfter(event.startTime),
          )
          .toList();
      eventsConflict[event] = conflicts;

      // complete conflict groups
      if (eventsConflictGroup[event] == null) {
        eventsConflictGroup[event] = {};
      }
      eventsConflictGroup[event]?.addAll(conflicts.toSet());
      for (var conflictEvent in conflicts) {
        if (eventsConflictGroup[conflictEvent] == null) {
          eventsConflictGroup[conflictEvent] = {};
        }
        eventsConflictGroup[conflictEvent]?.addAll(eventsConflictGroup[event]!);
      }
    }

    var eventsColumn = <Event, int>{};
    for (var eventEntry in eventsConflict.entries) {
      // no conflict
      if (eventEntry.value.isEmpty) {
        eventsColumn[eventEntry.key] = 0;
      }
      // conflicts : search free column (no already planned)
      else {
        var alreadyPlacedColumn = eventEntry.value
            .map((c) => eventsColumn[c])
            .where((e) => e != null)
            .toSet();
        var column = 0;
        while (alreadyPlacedColumn.contains(column)) {
          column++;
        }
        eventsColumn[eventEntry.key] = column;
      }
    }

    var organizedEvents = events.map((event) {
      var columnIndex = eventsColumn[event]!;

      // count column conflict for event
      // bug : no just see conflict of conflict event -> see recursive
      var columnSet = eventsConflictGroup[event]!
          .map((c) => eventsColumn[c])
          .where((e) => e != null)
          .toSet()
          .where((e) => e != null)
          .toSet();
      columnSet.add(columnIndex);
      var maxColumn = columnSet.length;

      // determine column width
      var widthWithPadding = width - (paddingLeft + paddingRight);
      var columnWidth = widthWithPadding / maxColumn;

      return OrganizedEvent(
        top: event.timedStartMinuteInDay * heightPerMinute,
        bottom: height - (event.timedEndMinuteInDay * heightPerMinute),
        left: (columnIndex * columnWidth) + paddingLeft,
        right: ((maxColumn - columnIndex - 1) * columnWidth) + paddingRight,
        startDuration: event.startTime,
        endDuration: event.endTime!,
        event: event,
      );
    }).toList();
    return organizedEvents;
  }
}
