import 'package:flutter/material.dart';

import '../utils/extension.dart';

const String defaultType = "default";

class Event {
  Event({
    this.columnIndex = 0,
    required this.startTime,
    this.endTime,
    this.isFullDay = false,
    this.title,
    this.description,
    this.data,
    this.eventType = defaultType,
    this.color = Colors.blue,
    this.textColor = Colors.white,
    this.daysIndex,
  }) {
    if (!isFullDay) {
      assert(endTime != null);
      assert(endTime!.isAfter(startTime));
    } else if (endTime != null) {
      assert(endTime!.isAfter(startTime));
    }
  }

  // generated unique id
  late UniqueKey uniqueId = UniqueKey();

  // column index in planner mode, 0 if not multiple column
  final int columnIndex;

  // event start time.
  // for full day event, set start of day
  final DateTime startTime;

  // event end time.
  // for full day event, set null
  // for multi days event, set dateTime of other day
  final DateTime? endTime;

  // full day event
  final bool isFullDay;

  // title showed in default event widget (can be overridden)
  final String? title;

  // description showed in default event widget (can be overridden)
  final String? description;

  // background color showed in default event widget (can be overridden)
  final Color color;

  // text color showed in default event widget (can be overridden)
  final Color textColor;

  // transported data for event
  final Object? data;

  // event type : generic object to easy manipulate event (arranger, widget...)
  final Object eventType;

  // multi days index
  final int? daysIndex;

  // effective start time for multi days events (startTime is for one day)
  DateTime? effectiveStartTime;

  // effective end time for multi days events (end is for one day)
  DateTime? effectiveEndTime;

  bool get isMultiDay => daysIndex != null;

  bool get isSingleMidnightCrossingTimedEvent {
    if (isFullDay) return false;
    final end = effectiveEndTime ?? endTime;
    if (end == null) return false;
    final start = effectiveStartTime ?? startTime;
    return end.withoutTime.difference(start.withoutTime).inDays == 1;
  }

  int get timedStartMinuteInDay {
    if (isMultiDay && (daysIndex ?? 0) > 0) return 0;
    return startTime.totalMinutes;
  }

  int get timedEndMinuteInDay {
    if (endTime == null) return timedStartMinuteInDay;

    if (isMultiDay && effectiveEndTime != null) {
      if ((daysIndex ?? 0) < _lastTimedSegmentIndex) {
        return minutesPerDay;
      }
      final end = effectiveEndTime!;
      if (end.totalMinutes == 0 &&
          end.withoutTime.isAfter(startTime.withoutTime)) {
        return minutesPerDay;
      }
      return end.totalMinutes;
    }

    if (endTime!.totalMinutes == 0 &&
        endTime!.withoutTime.isAfter(startTime.withoutTime)) {
      return minutesPerDay;
    }
    return endTime!.totalMinutes;
  }

  int get _lastTimedSegmentIndex {
    final end = effectiveEndTime ?? endTime;
    if (end == null) return 0;
    final start = effectiveStartTime ?? startTime;
    final daySpan = end.withoutTime.difference(start.withoutTime).inDays;
    if (daySpan > 0 && end.totalMinutes == 0) return daySpan - 1;
    return daySpan;
  }

  static const int minutesPerDay = 24 * 60;

  Event copyWith({
    final int? columnIndex,
    final DateTime? startTime,
    final DateTime? endTime,
    final bool? isFullDay,
    final String? title,
    final String? description,
    final Color? color,
    final Color? textColor,
    final Object? data,
    final Object? eventType,
    final int? daysIndex,
    final DateTime? effectiveStartTime,
    final DateTime? effectiveEndTime,
  }) {
    var event = Event(
      columnIndex: columnIndex ?? this.columnIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isFullDay: isFullDay ?? this.isFullDay,
      title: title ?? this.title,
      description: description ?? this.description,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
      data: data ?? this.data,
      eventType: eventType ?? this.eventType,
      daysIndex: daysIndex ?? this.daysIndex,
    );
    event.uniqueId = uniqueId;
    event.effectiveStartTime = effectiveStartTime ?? this.effectiveStartTime;
    event.effectiveEndTime = effectiveEndTime ?? this.effectiveEndTime;
    return event;
  }

  Duration? getDuration() {
    if (effectiveStartTime != null && effectiveEndTime != null) {
      return effectiveEndTime!.difference(effectiveStartTime!);
    }
    if (endTime != null) {
      return endTime!.difference(startTime);
    }
    return null;
  }
}
