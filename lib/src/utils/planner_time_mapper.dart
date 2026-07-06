import 'dart:math';

/// Shared geometry mapper between minute-of-day and planner Y coordinates.
class PlannerTimeMapper {
  const PlannerTimeMapper({
    required this.heightPerMinute,
    this.cellGapHeight = 0,
    this.paintGapAfterLastHour = false,
  })  : assert(heightPerMinute > 0),
        assert(cellGapHeight >= 0);

  final double heightPerMinute;
  final double cellGapHeight;
  final bool paintGapAfterLastHour;

  static const int minutesPerHour = 60;
  static const int hoursPerDay = 24;
  static const int minutesPerDay = minutesPerHour * hoursPerDay;

  double get hourHeight => heightPerMinute * minutesPerHour;

  double get hourBandHeight => hourHeight + cellGapHeight;

  int get hourGapCount => paintGapAfterLastHour ? hoursPerDay : hoursPerDay - 1;

  double totalDayHeight() {
    return (hourHeight * hoursPerDay) + (cellGapHeight * hourGapCount);
  }

  double minuteToY(double minute) {
    final clampedMinute = minute.clamp(0, minutesPerDay.toDouble());

    // Keep 24:00 at the bottom edge of the day.
    if (clampedMinute >= minutesPerDay) {
      return totalDayHeight();
    }

    final hourIndex = (clampedMinute ~/ minutesPerHour);
    final minuteInHour = clampedMinute - (hourIndex * minutesPerHour);
    return (hourIndex * hourBandHeight) + (minuteInHour * heightPerMinute);
  }

  /// Converts Y to minute-of-day using nearest-side behavior inside gaps.
  double yToMinute(double y) {
    final clampedY = y.clamp(0, totalDayHeight());

    if (clampedY >= totalDayHeight()) {
      return minutesPerDay.toDouble();
    }

    final bandIndex = (clampedY / hourBandHeight).floor();
    final localY = clampedY - (bandIndex * hourBandHeight);

    if (localY <= hourHeight) {
      final minuteInHour = localY / heightPerMinute;
      final minute = (bandIndex * minutesPerHour) + minuteInHour;
      return minute.clamp(0, minutesPerDay.toDouble());
    }

    // Gap zone: nearest-side snapping.
    final distanceToPreviousHour = localY - hourHeight;
    final distanceToNextHour = hourBandHeight - localY;

    if (distanceToPreviousHour <= distanceToNextHour || bandIndex >= hoursPerDay - 1) {
      final previousMinute = (bandIndex * minutesPerHour).toDouble() + (minutesPerHour - 0.001);
      return previousMinute.clamp(0, minutesPerDay.toDouble());
    }

    final nextMinute = ((bandIndex + 1) * minutesPerHour).toDouble();
    return min(nextMinute, minutesPerDay.toDouble());
  }

  // ── Extended-range helpers for multi-day slots ────────────────────

  /// Converts an absolute minute value (which may exceed [minutesPerDay])
  /// to a Y coordinate that spans multiple "virtual" days.
  ///
  /// The returned Y includes the full height of any preceding complete
  /// days plus the intra-day Y of the remaining minutes.
  ///
  /// Example: `minuteToYExtended(1500)` for a slot starting at 1:00 AM
  /// on day 2 returns `totalDayHeight() + minuteToY(60)`.
  double minuteToYExtended(double minute) {
    final fullDays = minute ~/ minutesPerDay;
    final intraMinute = minute - (fullDays * minutesPerDay);
    return (fullDays * totalDayHeight()) + minuteToY(intraMinute);
  }

  /// Inverse of [minuteToYExtended]: converts an extended Y coordinate
  /// back to an absolute minute value (from day 0 midnight).
  double yToMinuteExtended(double y) {
    final dayHeight = totalDayHeight();
    final fullDays = y ~/ dayHeight;
    final intraY = y - (fullDays * dayHeight);
    return (fullDays * minutesPerDay) + yToMinute(intraY);
  }

  /// Returns the number of complete 24-hour days in [totalMinutes].
  static int minutesToDays(int totalMinutes) => totalMinutes ~/ minutesPerDay;

  /// Returns the minute-of-day portion (0–1439) of [totalMinutes].
  static int minuteOfDay(int totalMinutes) => totalMinutes % minutesPerDay;
}
