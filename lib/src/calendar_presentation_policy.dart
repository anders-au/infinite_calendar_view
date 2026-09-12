/// Shared presentation rules for calendar lanes.
abstract final class CalendarPresentationPolicy {
  static const timedDayLaneThreshold = Duration(hours: 24);

  /// Returns whether a calendar item belongs in the full-day lane.
  ///
  /// This is a presentation decision only. It does not change the source
  /// event's timestamps or enforcement semantics.
  static bool rendersInFullDayRegion({
    required DateTime start,
    required DateTime end,
    required bool sourceIsAllDay,
  }) {
    if (sourceIsAllDay) return true;
    final duration = end.difference(start);
    return !duration.isNegative && duration > timedDayLaneThreshold;
  }
}
