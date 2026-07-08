import 'package:flutter/foundation.dart';

import '../utils/extension.dart';
import '../utils/planner_time_mapper.dart';
import 'slot_config.dart';
import 'slot_selection.dart';

/// Pure validation functions that clamp a proposed [CalendarSlot] to
/// valid boundaries.
///
/// Every function takes a [proposed] slot (the raw anchor + delta result)
/// and an [anchor] (the immutable drag-start snapshot) and returns a
/// clamped copy.  The anchor is used to determine the original duration
/// for shift-mode safety fallbacks.
///
/// These have **zero** Flutter dependencies — they are fully unit-testable.
class SlotConstraints {
  const SlotConstraints._(); // namespace only

  /// Clamps [proposed] based on [mode] and [config].
  ///
  /// Returns a new [CalendarSlot] guaranteed to be valid according to
  /// [config]'s boundary rules.  If the proposal is already valid it is
  /// returned unchanged.
  static CalendarSlot clamp({
    required CalendarSlot proposed,
    required CalendarSlot anchor,
    required DragMode mode,
    required SlotInteractionConfig config,
  }) {
    switch (mode) {
      case DragMode.shift:
        return _clampShift(proposed, anchor, config);
      case DragMode.extendStart:
        return _clampExtendStart(proposed, anchor, config);
      case DragMode.extendEnd:
        return _clampExtendEnd(proposed, anchor, config);
    }
  }

  // ── shift ────────────────────────────────────────────────────────────

  /// Shift preserves duration.  Clamp start so the entire slot stays
  /// within the valid time range.
  static CalendarSlot _clampShift(
    CalendarSlot proposed,
    CalendarSlot anchor,
    SlotInteractionConfig config,
  ) {
    if (proposed.isAllDay) {
      // All-day slots can shift freely across days — no time clamping.
      return proposed;
    }

    final dur = anchor.durationInMinutes;
    var newStart = proposed.startDateTime;
    var newEnd = proposed.endDateTime;

    if (debugSlotDrag) {
      debugPrint('[SlotConstraints] _clampShift IN  '
          'proposedStart=${proposed.startDateTime.toIso8601String()}  '
          'proposedEnd=${proposed.endDateTime.toIso8601String()}  '
          'anchorDur=${dur}min  '
          'maxDurationMinutes=${config.maxDurationMinutes}');
    }

    // Clamp start to not go before 00:00 of its calendar day.
    final earliestStart = _earliestAllowedStart(newStart);
    if (newStart.isBefore(earliestStart)) {
      newStart = earliestStart;
      newEnd = newStart.add(Duration(minutes: dur));
      if (debugSlotDrag) debugPrint('[SlotConstraints] _clampShift clamped start to $earliestStart');
    }

    // Clamp end to not exceed the allowed column span.
    final latestEnd = _latestAllowedEnd(newStart, dur, config);
    if (newEnd.isAfter(latestEnd)) {
      newEnd = latestEnd;
      newStart = newEnd.subtract(Duration(minutes: dur));
      if (debugSlotDrag) debugPrint('[SlotConstraints] _clampShift clamped end to $latestEnd');
    }

    // Safety: ensure duration is always preserved.
    if (!newEnd.isAfter(newStart)) {
      newStart = _earliestAllowedStart(proposed.startDateTime);
      newEnd = newStart.add(Duration(minutes: dur));
      final latest = _latestAllowedEnd(newStart, dur, config);
      if (newEnd.isAfter(latest)) {
        newEnd = latest;
        newStart = newEnd.subtract(Duration(minutes: dur));
      }
      if (debugSlotDrag) debugPrint('[SlotConstraints] _clampShift SAFETY reset to start=$newStart end=$newEnd');
    }

    if (debugSlotDrag) {
      debugPrint('[SlotConstraints] _clampShift OUT '
          'start=${newStart.toIso8601String()}  '
          'end=${newEnd.toIso8601String()}  '
          'dur=${newEnd.difference(newStart).inMinutes}min  '
          'changed=${newStart != proposed.startDateTime || newEnd != proposed.endDateTime}');
    }

    if (newStart == proposed.startDateTime && newEnd == proposed.endDateTime) {
      return proposed;
    }
    return proposed.withDates(newStart, newEnd);
  }

  // ── extend start ─────────────────────────────────────────────────────

  static CalendarSlot _clampExtendStart(
    CalendarSlot proposed,
    CalendarSlot anchor,
    SlotInteractionConfig config,
  ) {
    if (proposed.isAllDay) {
      // All-day: just ensure startDate ≤ endDate.
      if (proposed.startDateTime.isAfter(proposed.endDateTime)) {
        return proposed.withDates(
          proposed.endDateTime.subtract(const Duration(days: 1)),
          proposed.endDateTime,
        );
      }
      return proposed;
    }

    final minDur = config.minDurationMinutes;
    var newStart = proposed.startDateTime;
    final end = proposed.endDateTime; // unchanged by extendStart

    // Start cannot go before midnight of its calendar day.
    final earliest = _earliestAllowedStart(newStart);
    if (newStart.isBefore(earliest)) {
      newStart = earliest;
    }

    // Start + minDuration must be ≤ end.
    final latestStart = end.subtract(Duration(minutes: minDur));
    if (newStart.isAfter(latestStart)) {
      newStart = latestStart;
    }

    // Enforce maxDurationMinutes: end − newStart ≤ maxDur.
    final maxDur = _effectiveMaxDurationMinutes(config);
    final duration = end.difference(newStart).inMinutes;
    if (duration > maxDur) {
      newStart = end.subtract(Duration(minutes: maxDur));
    }

    // Safety: if start ≥ end, clamp to end − minDuration.
    if (!end.isAfter(newStart)) {
      newStart = end.subtract(Duration(minutes: minDur));
      return proposed.withDates(newStart, end);
    }

    if (newStart == proposed.startDateTime) return proposed;
    return proposed.withDates(newStart, end);
  }

  // ── extend end ───────────────────────────────────────────────────────

  static CalendarSlot _clampExtendEnd(
    CalendarSlot proposed,
    CalendarSlot anchor,
    SlotInteractionConfig config,
  ) {
    if (proposed.isAllDay) {
      // All-day: just ensure endDate ≥ startDate.
      if (proposed.endDateTime.isBefore(proposed.startDateTime)) {
        return proposed.withDates(
          proposed.startDateTime,
          proposed.startDateTime.add(const Duration(days: 1)),
        );
      }
      return proposed;
    }

    final minDur = config.minDurationMinutes;
    final start = proposed.startDateTime; // unchanged by extendEnd
    var newEnd = proposed.endDateTime;

    // End cannot go before start + minDuration.
    final earliestEnd = start.add(Duration(minutes: minDur));
    if (newEnd.isBefore(earliestEnd)) {
      newEnd = earliestEnd;
    }

    // Compute the last allowed minute for the end.
    final maxDur = _effectiveMaxDurationMinutes(config);

    // Compute the duration from start of the proposed end.
    final endDurationFromStart = newEnd.difference(start).inMinutes;

    if (endDurationFromStart > maxDur) {
      // Clamp end to the max duration.
      newEnd = start.add(Duration(minutes: maxDur));
    }

    // Safety: if end ≤ start, clamp to start + minDuration.
    if (!newEnd.isAfter(start)) {
      newEnd = start.add(Duration(minutes: minDur));
      return proposed.withDates(start, newEnd);
    }

    if (newEnd == proposed.endDateTime) return proposed;
    return proposed.withDates(start, newEnd);
  }

  // ── boundary helpers ─────────────────────────────────────────────────

  /// Returns the earliest [DateTime] that [dt] is allowed to start at.
  /// Always clamps to midnight of the current calendar day — the start
  /// handle can never move into a previous day.
  static DateTime _earliestAllowedStart(DateTime dt) {
    return dt.withoutTime;
  }

  /// Returns the effective max column span, defaulting to 2 when
  /// [config.maxDurationMinutes] is null.  This allows slots to extend into
  /// the next day by default (2 days / 2880 minutes).
  static int _effectiveMaxDurationMinutes(SlotInteractionConfig config) {
    final d = config.maxDurationMinutes;
    if (d == null) return 2 * PlannerTimeMapper.minutesPerDay;
    return d;
  }

  /// Returns the latest [DateTime] that a slot of [durationMinutes]
  /// starting at [start] is allowed to end at.
  static DateTime _latestAllowedEnd(
    DateTime start,
    int durationMinutes,
    SlotInteractionConfig config,
  ) {
    final maxDur = _effectiveMaxDurationMinutes(config);
    final effectiveDur = durationMinutes.clamp(0, maxDur).toInt();
    return start.add(Duration(minutes: effectiveDur));
  }
}
