import 'dart:math';
import 'dart:ui';

import '../utils/extension.dart';
import '../utils/planner_time_mapper.dart';
import 'slot_config.dart';
import 'slot_selection.dart';

/// Pixel ↔ time geometry for slot positioning and drag calculations.
///
/// Wraps a [PlannerTimeMapper] and provides convenience methods for
/// converting between pixel offsets and time units, computing slot
/// rectangles, and determining handle hit zones.
class SlotGeometry {
  const SlotGeometry({
    required this.timeMapper,
    required this.dayWidth,
    this.dayTopPadding = 0,
    this.cellGapWidthPadding = 0,
  });

  final PlannerTimeMapper timeMapper;
  final double dayWidth;

  /// Top padding applied by the planner to the time-grid area.
  final double dayTopPadding;

  /// Half the cell-gap width, used to inset column content from day edges.
  final double cellGapWidthPadding;

  double get heightPerMinute => timeMapper.heightPerMinute;

  // ── pixel ↔ minute ───────────────────────────────────────────────────

  /// Converts a vertical pixel delta to a snapped minute delta.
  int pixelDeltaToMinutes(double dy, int stepMinutes) {
    final raw = dy / heightPerMinute;
    return (stepMinutes * (raw / stepMinutes).round()).round();
  }

  /// Converts a horizontal pixel delta to whole days.
  int pixelDeltaToDays(double dx) {
    if (dayWidth <= 0) return 0;
    return (dx / dayWidth).round();
  }

  /// Minute-of-day → Y pixel within a single day column.
  double minuteToY(double minute) => timeMapper.minuteToY(minute);

  /// Y pixel → minute-of-day.
  double yToMinute(double y) => timeMapper.yToMinute(y);

  /// Extended Y → absolute minute (multi-day).
  double yToMinuteExtended(double y) => timeMapper.yToMinuteExtended(y);

  /// Absolute minute → extended Y (multi-day).
  double minuteToYExtended(double minute) =>
      timeMapper.minuteToYExtended(minute);

  /// Full height of one day column (including gaps).
  double get totalDayHeight => timeMapper.totalDayHeight();

  // ── slot rect ────────────────────────────────────────────────────────

  /// Computes the pixel rectangle for [slot] in the viewport, given the
  /// current horizontal [scrollOffset] and per-column positioning.
  ///
  /// [columnPositions] is `[startOffset, endOffset]` within the padded
  /// day width (obtained from [ColumnsParam.getColumPositions]).
  ///
  /// [viewportDayOffset] is the pixel offset of the slot's start day
  /// relative to the planner viewport's left edge (i.e.
  /// `dayIndex * dayWidth - scrollOffset`).
  Rect computeSlotRect({
    required CalendarSlot slot,
    required double scrollOffset,
    required List<double> columnPositions,
    required double plannerHeight,
    int? startDayIndex,
  }) {
    if (slot.isAllDay) {
      // All-day slots are positioned by the all-day bar overlay, not here.
      return Rect.zero;
    }

    final startDayDiff = startDayIndex ??
        _dayDiffFromInitial(slot.startDateTime); // overridden by caller
    final viewportX = startDayDiff * dayWidth - scrollOffset;
    final left = viewportX + cellGapWidthPadding + columnPositions[0];

    final startMinute = slot.startDateTime.totalMinutes.toDouble();
    final endMinute =
        (startMinute + slot.durationInMinutes).toDouble();

    final top = minuteToY(startMinute) + dayTopPadding;
    double bottom = minuteToY(endMinute) + dayTopPadding;

    // Gap correction: when ending on an hour boundary, pull back.
    if (timeMapper.cellGapHeight > 0 &&
        endMinute > 0 &&
        endMinute < PlannerTimeMapper.minutesPerDay &&
        endMinute % PlannerTimeMapper.minutesPerHour == 0) {
      bottom -= timeMapper.cellGapHeight;
    }

    final width = columnPositions[1] - columnPositions[0];

    return Rect.fromLTRB(left, top, left + width, bottom);
  }

  /// Computes the multi-day slot rectangle spanning [totalDays] columns.
  Rect computeMultiDaySlotRect({
    required CalendarSlot slot,
    required double scrollOffset,
    required List<double> columnPositions,
    required double plannerHeight,
    required int startDayIndex,
  }) {
    if (slot.isAllDay) return Rect.zero;

    final viewportX = startDayIndex * dayWidth - scrollOffset;
    final left = viewportX + cellGapWidthPadding + columnPositions[0];
    final width = (slot.totalDaysSpanned - 1) * dayWidth +
        (columnPositions[1] - columnPositions[0]);
    final top = dayTopPadding;
    final height = plannerHeight - dayTopPadding; // bottom padding excluded

    return Rect.fromLTRB(left, top, left + width, top + height);
  }

  /// Returns the day index (relative to some reference) for a DateTime.
  /// Callers provide their own reference via [initialDate].
  int dayIndexFor(DateTime date, DateTime initialDate) {
    return date.withoutTime.difference(initialDate.withoutTime).inDays;
  }

  int _dayDiffFromInitial(DateTime dt) => 0; // caller overrides

  // ── handle zones ─────────────────────────────────────────────────────

  /// Returns the rect for the start (top) resize handle within [slotRect].
  static Rect startHandleRect(Rect slotRect, double zoneSize) {
    return Rect.fromLTRB(
      slotRect.left,
      slotRect.top,
      slotRect.right,
      min(slotRect.top + zoneSize, slotRect.bottom),
    );
  }

  /// Returns the rect for the end (bottom) resize handle within [slotRect].
  static Rect endHandleRect(Rect slotRect, double zoneSize) {
    return Rect.fromLTRB(
      slotRect.left,
      max(slotRect.bottom - zoneSize, slotRect.top),
      slotRect.right,
      slotRect.bottom,
    );
  }

  /// Returns the rect for the shift (middle) zone within [slotRect].
  static Rect bodyRect(Rect slotRect, double zoneSize) {
    final top = min(slotRect.top + zoneSize, slotRect.bottom);
    final bottom = max(slotRect.bottom - zoneSize, slotRect.top);
    return Rect.fromLTRB(slotRect.left, top, slotRect.right, bottom);
  }

  // ── hit testing ──────────────────────────────────────────────────────

  /// Determines which drag mode the pointer at [localPosition] within
  /// [slotRect] maps to.  Returns null if the position is outside the slot.
  static DragMode? hitTest(
    Offset localPosition,
    Rect slotRect,
    SlotInteractionConfig config,
  ) {
    if (!slotRect.contains(localPosition)) return null;

    final distToTop = localPosition.dy - slotRect.top;
    final distToBottom = slotRect.bottom - localPosition.dy;
    final zoneSize = config.handleZoneSize;

    // When zones overlap (very short slot), pick the closest edge.
    if (config.enableResize && config.enableExtendStart && distToTop <= zoneSize) {
      if (!config.enableExtendEnd || distToTop <= distToBottom) {
        return DragMode.extendStart;
      }
    }
    if (config.enableResize && config.enableExtendEnd && distToBottom <= zoneSize) {
      return DragMode.extendEnd;
    }
    if (config.enableShift) {
      return DragMode.shift;
    }
    return null;
  }
}
