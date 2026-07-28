import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../utils/extension.dart';
import '../utils/planner_time_mapper.dart';
import 'slot_config.dart';

/// Set to true to print slot drag diagnostics to the console.
bool debugSlotDrag = false;

/// Unified immutable model for an interactive slot selection in the planner.
///
/// Replaces the previous `CalendarSlot` sealed class hierarchy
/// (`TimedSlotSelection` + `AllDaySlotSelection`).  A single class with an
/// [isAllDay] flag covers both timed time-grid slots and all-day-bar pills.
///
/// Every drag-update produces a **new** instance — the model is fully
/// immutable.  The anchor snapshot captured at drag-start never mutates,
/// which eliminates the stale-state bugs present in the old system.
class CalendarSlot {
  /// The column index within the day (0 when single-column).
  final int columnIndex;

  /// The date (and time, for timed slots) where the gesture started.
  /// Preserved across drags so consumers can detect the original tap point.
  final DateTime initialStartDate;

  /// Start date-time.  Always carries a full time component.
  ///
  /// * Timed slots use the full value.
  /// * All-day slots set the time to midnight ([DateTime.hour] == 0,
  ///   [DateTime.minute] == 0).
  final DateTime startDateTime;

  /// Duration of the slot.  Always positive (zero-length slots are not
  /// valid).  Together with [startDateTime] this fully defines the slot
  /// extents — [endDateTime] is derived.
  ///
  /// * Timed slots store their exact duration (e.g. 60 minutes).
  /// * All-day slots store `days × 1440` minutes so a 3-day all-day slot
  ///   has a duration of 4320 minutes.
  final Duration duration;

  /// When true, the slot renders as a horizontal pill in the all-day bar
  /// instead of a vertical block in the time grid.
  final bool isAllDay;

  CalendarSlot({
    required this.columnIndex,
    required this.initialStartDate,
    required this.startDateTime,
    required this.duration,
    this.isAllDay = false,
  }) : assert(!duration.isNegative, 'duration must not be negative');

  // ── factories ────────────────────────────────────────────────────────

  /// Creates a timed slot from a tap/gesture on the time grid.
  ///
  /// [startDateTime] is typically the rounded tap time.
  /// [durationMinutes] defaults to 60.
  factory CalendarSlot.fromTap({
    required int columnIndex,
    required DateTime startDateTime,
    int durationMinutes = 60,
  }) {
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: startDateTime,
      startDateTime: startDateTime,
      duration: Duration(minutes: durationMinutes),
    );
  }

  /// Creates an all-day slot from a tap/gesture on the all-day bar.
  ///
  /// [startDate] and [endDate] are date-only values (time is ignored).
  /// [endDate] is inclusive — a single-day selection has
  /// `startDate == endDate`.
  factory CalendarSlot.allDayFromTap({
    required int columnIndex,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final startDay = startDate.withoutTime;
    final endDay = endDate.withoutTime;
    final days = endDay.difference(startDay).inDays + 1;
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: startDay,
      startDateTime: startDay,
      duration: Duration(days: days),
      isAllDay: true,
    );
  }

  // ── derived ──────────────────────────────────────────────────────────

  /// End date-time, computed from [startDateTime] + [duration].
  ///
  /// * Timed slots: the actual wall-clock end.
  /// * All-day slots: midnight of the day after the last spanned day
  ///   (exclusive end).  For a 3-day slot starting Jan 1, this is
  ///   Jan 4 00:00.
  DateTime get endDateTime => startDateTime.add(duration);

  /// Duration in whole minutes.
  int get durationInMinutes => duration.inMinutes;

  /// Effective end, treating midnight as the last instant of the previous
  /// day.  A slot ending at 00:00:00.000 is adjusted back by 1 µs so it
  /// belongs to the previous calendar day for span calculations.
  DateTime get effectiveEndDateTime {
    final end = endDateTime;
    if (_isMidnight(end)) {
      return end.subtract(const Duration(microseconds: 1));
    }
    return end;
  }

  /// Minute-of-day for the end (1..1440).  Midnight → 1440.
  int get endMinuteOfDay {
    final total = startDateTime.totalMinutes + durationInMinutes;
    final mod = total % PlannerTimeMapper.minutesPerDay;
    return (mod == 0 && total > 0) ? PlannerTimeMapper.minutesPerDay : mod;
  }

  /// Number of calendar days spanned (always ≥ 1).
  ///
  /// Uses [effectiveEndDateTime] so a slot ending at midnight is still
  /// treated as single-day.
  int get totalDaysSpanned {
    if (isAllDay) {
      // All-day duration is in whole days; compute span directly.
      final days = duration.inDays;
      return days > 0 ? days : 1;
    }
    return effectiveEndDateTime.withoutTime
            .difference(startDateTime.withoutTime)
            .inDays +
        1;
  }

  // ── conversion ───────────────────────────────────────────────────────

  /// Converts this timed slot to an all-day slot, preserving the calendar
  /// day span.  Time components become midnight-based.
  ///
  /// A timed slot from Jan 1 22:00 → Jan 2 06:00 (2 calendar days) becomes
  /// an all-day slot Jan 1 → Jan 2 (inclusive).
  CalendarSlot toAllDay() {
    if (isAllDay) return this;
    final days = totalDaysSpanned;
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: startDateTime.withoutTime,
      duration: Duration(days: days),
      isAllDay: true,
    );
  }

  /// Converts this all-day slot to a timed slot spanning midnight-to-
  /// midnight for each day.
  ///
  /// An all-day slot Jan 1 → Jan 3 (3 days) becomes timed
  /// Jan 1 00:00 → Jan 4 00:00.
  CalendarSlot toTimed() {
    if (!isAllDay) return this;
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: startDateTime,
      duration: duration,
      isAllDay: false,
    );
  }

  // ── delta application ────────────────────────────────────────────────

  /// Computes a proposed new slot by applying [delta] (in logical pixels)
  /// relative to this anchor, using [config] for snap increments and
  /// [mode] to determine which edges move.
  ///
  /// This is intentionally a **pure function** — it does not validate or
  /// clamp.  Use [SlotConstraints] to clamp the result afterward.
  CalendarSlot applyDelta(
    Offset delta, {
    required SlotInteractionConfig config,
    required DragMode mode,
    required double dayWidth,
    required double heightPerMinute,
  }) {
    final days = config.enableHorizontalAxis
        ? (delta.dx / dayWidth).round()
        : 0;
    final rawMinuteDelta = config.enableVerticalAxis
        ? delta.dy / heightPerMinute
        : 0.0;

    final dayShift = days * PlannerTimeMapper.minutesPerDay;

    CalendarSlot result;
    switch (mode) {
      case DragMode.shift:
        final newStart = _snapDateTime(
          startDateTime.add(
            Duration(
              minutes: dayShift + rawMinuteDelta.round(),
            ),
          ),
          config.stepMinutes,
        );
        result = withStart(newStart);
        break;

      case DragMode.extendStart:
        final newStart = _snapDateTime(
          startDateTime.add(
            Duration(
              minutes: dayShift + rawMinuteDelta.round(),
            ),
          ),
          config.stepMinutes,
        );
        final newDur = endDateTime.difference(newStart);
        if (newDur.inMinutes <= 0) {
          final minDur = isAllDay ? PlannerTimeMapper.minutesPerDay : 1;
          result = withDates(
            endDateTime.subtract(Duration(minutes: minDur)),
            endDateTime,
          );
        } else {
          result = withStart(newStart).copyWith(duration: newDur);
        }
        break;

      case DragMode.extendEnd:
        final newEnd = _snapDateTime(
          endDateTime.add(
            Duration(
              minutes: dayShift + rawMinuteDelta.round(),
            ),
          ),
          config.stepMinutes,
        );
        final newDur = newEnd.difference(startDateTime);
        if (newDur.inMinutes <= 0) {
          final minDur = isAllDay ? PlannerTimeMapper.minutesPerDay : 1;
          result = withDuration(Duration(minutes: minDur));
        } else {
          result = withDuration(newDur);
        }
        break;
    }

    if (debugSlotDrag) {
      final pkg =
          'package:infinite_calendar_view/src/interactive_slot/slot_selection.dart';
      debugPrint(
        '[$pkg] applyDelta  '
        'mode=$mode  '
        'delta=(${delta.dx.toStringAsFixed(1)},${delta.dy.toStringAsFixed(1)})  '
        'days=$days  rawMinDelta=$rawMinuteDelta  dayShift=$dayShift  '
        'anchorStart=$startDateTime  anchorEnd=$endDateTime  '
        'resultStart=${result.startDateTime}  resultEnd=${result.endDateTime}  '
        'resultDays=${result.totalDaysSpanned}',
      );
    }

    return result;
  }

  // ── copyWith ─────────────────────────────────────────────────────────

  CalendarSlot copyWith({
    int? columnIndex,
    DateTime? initialStartDate,
    DateTime? startDateTime,
    Duration? duration,
    bool? isAllDay,
  }) {
    return CalendarSlot(
      columnIndex: columnIndex ?? this.columnIndex,
      initialStartDate: initialStartDate ?? this.initialStartDate,
      startDateTime: startDateTime ?? this.startDateTime,
      duration: duration ?? this.duration,
      isAllDay: isAllDay ?? this.isAllDay,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────

  /// Returns a copy with [newStart], preserving [duration].
  CalendarSlot withStart(DateTime newStart) {
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: newStart,
      duration: duration,
      isAllDay: isAllDay,
    );
  }

  /// Returns a copy with [newDuration], preserving [startDateTime].
  CalendarSlot withDuration(Duration newDuration) {
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: startDateTime,
      duration: newDuration,
      isAllDay: isAllDay,
    );
  }

  /// Returns a copy with [newStart] and [newEnd], computing [duration]
  /// from the two dates.  Public so [SlotConstraints] can produce clamped
  /// copies.
  ///
  /// Unlike the main constructor this does **not** assert ordering — it is
  /// used internally during drag computation where the constraints layer
  /// is responsible for final validation.
  CalendarSlot withDates(DateTime newStart, DateTime newEnd) {
    // Swap if inverted so the slot is always well-formed.
    if (newEnd.isBefore(newStart)) {
      final tmp = newStart;
      newStart = newEnd;
      newEnd = tmp;
    }
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: newStart,
      duration: newEnd.difference(newStart),
      isAllDay: isAllDay,
    );
  }

  static DateTime _snapDateTime(DateTime value, int step) {
    final minuteOfDay = value.hour * 60 + value.minute;
    final snappedMinute = step * (minuteOfDay / step).round();
    return DateTime(
      value.year,
      value.month,
      value.day,
    ).add(Duration(minutes: snappedMinute));
  }

  static bool _isMidnight(DateTime dt) =>
      dt.hour == 0 &&
      dt.minute == 0 &&
      dt.second == 0 &&
      dt.millisecond == 0 &&
      dt.microsecond == 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarSlot &&
      columnIndex == other.columnIndex &&
      initialStartDate == other.initialStartDate &&
      startDateTime == other.startDateTime &&
      duration == other.duration &&
      isAllDay == other.isAllDay;

  @override
  int get hashCode => Object.hash(
    columnIndex,
    initialStartDate,
    startDateTime,
    duration,
    isAllDay,
  );

  @override
  String toString() =>
      'CalendarSlot(column: $columnIndex, '
      'start: $startDateTime, dur: $duration, '
      'allDay: $isAllDay, days: $totalDaysSpanned)';
}

/// Drag interaction modes for the slot.
///
/// Each mode can be individually enabled/disabled via [SlotInteractionConfig].
enum DragMode {
  /// Move the entire slot — start and end shift by the same amount.
  shift,

  /// Resize from the start handle — only the start time changes.
  extendStart,

  /// Resize from the end handle — only the end time changes.
  extendEnd,
}
