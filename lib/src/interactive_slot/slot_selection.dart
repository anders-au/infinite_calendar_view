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

  /// End date-time.  Always carries a full time component.
  ///
  /// * Timed slots use the full value.
  /// * All-day slots set the time to 23:59:59.999 of the last day so
  ///   [dayCount] matches the number of calendar days spanned.
  ///
  /// Must be strictly after [startDateTime].
  final DateTime endDateTime;

  /// When true, the slot renders as a horizontal pill in the all-day bar
  /// instead of a vertical block in the time grid.
  final bool isAllDay;

  CalendarSlot({
    required this.columnIndex,
    required this.initialStartDate,
    required this.startDateTime,
    required this.endDateTime,
    this.isAllDay = false,
  }) : assert(!endDateTime.isBefore(startDateTime),
            'endDateTime must not be before startDateTime');

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
      endDateTime: startDateTime.add(Duration(minutes: durationMinutes)),
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
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: startDay,
      startDateTime: startDay,
      endDateTime: endDay.add(const Duration(days: 1)),
      isAllDay: true,
    );
  }

  // ── derived ──────────────────────────────────────────────────────────

  /// Duration between [startDateTime] and [endDateTime].
  Duration get duration => endDateTime.difference(startDateTime);

  /// Duration in whole minutes.
  int get durationInMinutes => duration.inMinutes;

  /// Effective end, treating midnight as the last instant of the previous
  /// day.  A slot ending at 00:00:00.000 is adjusted back by 1 µs so it
  /// belongs to the previous calendar day for span calculations.
  DateTime get effectiveEndDateTime {
    if (_isMidnight(endDateTime)) {
      return endDateTime.subtract(const Duration(microseconds: 1));
    }
    return endDateTime;
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
      // All-day: endDateTime is midnight of day after last day.
      // E.g. Jan 1 00:00 → Jan 2 00:00 = 1 day.
      return endDateTime.withoutTime
              .difference(startDateTime.withoutTime)
              .inDays;
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
    final startDay = startDateTime.withoutTime;
    final endDay = effectiveEndDateTime.withoutTime;
    // endDateTime exclusive: midnight of the day AFTER the last day.
    final exclusiveEnd = endDay.add(const Duration(days: 1));
    return CalendarSlot(
      columnIndex: columnIndex,
      initialStartDate: initialStartDate,
      startDateTime: startDay,
      endDateTime: exclusiveEnd,
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
      endDateTime: endDateTime, // already midnight of day after last day
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
    final minuteDelta = config.enableVerticalAxis
        ? _roundMinutes(delta.dy / heightPerMinute, config.stepMinutes)
        : 0;

    final totalMinuteShift = days * PlannerTimeMapper.minutesPerDay + minuteDelta;

    CalendarSlot result;
    switch (mode) {
      case DragMode.shift:
        final newStart = startDateTime.add(Duration(minutes: totalMinuteShift));
        final newEnd = endDateTime.add(Duration(minutes: totalMinuteShift));
        if (!newEnd.isAfter(newStart)) {
          result = withDates(startDateTime, startDateTime.add(const Duration(minutes: 1)));
        } else {
          result = withDates(newStart, newEnd);
        }
        break;

      case DragMode.extendStart:
        final newStart = startDateTime.add(Duration(minutes: totalMinuteShift));
        if (!endDateTime.isAfter(newStart)) {
          result = withDates(endDateTime.subtract(const Duration(minutes: 1)), endDateTime);
        } else {
          result = withDates(newStart, endDateTime);
        }
        break;

      case DragMode.extendEnd:
        final newEnd = endDateTime.add(Duration(minutes: totalMinuteShift));
        if (!newEnd.isAfter(startDateTime)) {
          result = withDates(startDateTime, startDateTime.add(const Duration(minutes: 1)));
        } else {
          result = withDates(startDateTime, newEnd);
        }
        break;
    }

    if (debugSlotDrag) {
      final pkg = 'package:infinite_calendar_view/src/interactive_slot/slot_selection.dart';
      debugPrint('[$pkg] applyDelta  '
          'mode=$mode  '
          'delta=(${delta.dx.toStringAsFixed(1)},${delta.dy.toStringAsFixed(1)})  '
          'days=$days  minDelta=$minuteDelta  totalShift=$totalMinuteShift  '
          'anchorStart=$startDateTime  anchorEnd=$endDateTime  '
          'resultStart=${result.startDateTime}  resultEnd=${result.endDateTime}  '
          'resultDays=${result.totalDaysSpanned}');
    }

    return result;
  }

  // ── copyWith ─────────────────────────────────────────────────────────

  CalendarSlot copyWith({
    int? columnIndex,
    DateTime? initialStartDate,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? isAllDay,
  }) {
    return CalendarSlot(
      columnIndex: columnIndex ?? this.columnIndex,
      initialStartDate: initialStartDate ?? this.initialStartDate,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      isAllDay: isAllDay ?? this.isAllDay,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────

  /// Returns a copy with [newStart] and [newEnd], preserving all other fields.
  /// Public so [SlotConstraints] can produce clamped copies.
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
      endDateTime: newEnd,
      isAllDay: isAllDay,
    );
  }

  static int _roundMinutes(double raw, int step) {
    return (step * (raw / step).round()).round();
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
      endDateTime == other.endDateTime &&
      isAllDay == other.isAllDay;

  @override
  int get hashCode => Object.hash(
        columnIndex,
        initialStartDate,
        startDateTime,
        endDateTime,
        isAllDay,
      );

  @override
  String toString() =>
      'CalendarSlot(column: $columnIndex, '
      'start: $startDateTime, end: $endDateTime, '
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
