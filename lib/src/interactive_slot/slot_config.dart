import 'package:flutter/widgets.dart';

import 'slot_selection.dart';

/// Configuration for the interactive slot drag/resize and creation system.
///
/// Pass an instance to [SlotOverlay], [AllDaySlotOverlay], or set on
/// [DayParam.slotInteractionConfig] / [FullDayParam.allDaySlotInteractionConfig]
/// to control which interactions are available and how they behave.
///
/// This class replaces the legacy [SlotSelectionParam] and
/// [AllDaySlotSelectionParam] with a single unified configuration object.
class SlotInteractionConfig {
  const SlotInteractionConfig({
    this.stepMinutes = 15,
    this.stepMinutesResolver,
    this.enableShift = true,
    this.enableResizeStart = true,
    this.enableResizeEnd = true,
    this.enableHorizontalAxis = true,
    this.enableVerticalAxis = true,
    this.minDurationMinutes = 15,
    this.maxDurationMinutes,
    this.showHandles = true,
    this.handleZoneSize = 20.0,
    this.dragThreshold = 6.0,
    this.longPressDuration = const Duration(milliseconds: 300),
    this.accentColor,
    this.slotBorderRadius = 8.0,
    this.showDefaultSlotText = true,
    this.use24HourFormat = true,
    this.overlappingEventOpacity = 0.4,
    this.showTimeIndicators = true,
    this.timeIndicatorColor,
    this.timeIndicatorTextStyle,
    this.onChanged,
    this.onTap,
    this.onLongPress,
    this.onDragStart,
    this.onDragEnd,
    this.enableTapSlotSelection = false,
    this.enableLongPressSlotSelection = false,
    this.enableDoubleTapSlotSelection = false,
    this.clearWhenBackgroundTap = true,
    this.enableResize = true,
    this.defaultDurationMinutes,
    this.slotContentBuilder,
    this.slotBuilder,
    this.topHandleBuilder,
    this.bottomHandleBuilder,
  }) : assert(
         overlappingEventOpacity >= 0 && overlappingEventOpacity <= 1,
         'overlappingEventOpacity must be between 0 and 1',
       );

  // ── drag behaviour ───────────────────────────────────────────────────

  /// Snap increment in minutes for timed-slot drag/resize operations.
  /// Defaults to 15 minutes.
  ///
  /// When [stepMinutesResolver] is non-null it takes precedence over
  /// this value on a per-column, per-date basis.
  final int stepMinutes;

  /// Optional per-column/date override for [stepMinutes].
  ///
  /// Receives the slot's [CalendarSlot.columnIndex] and
  /// [CalendarSlot.startDateTime] and returns the snap increment to use
  /// for that specific drag operation.  When null (the default),
  /// [stepMinutes] is used uniformly.
  ///
  /// This replaces the legacy [SlotSelectionParam.dragIncrementMinutes].
  final int Function(int columnIndex, DateTime date)? stepMinutesResolver;

  /// Allow moving the entire slot (both start and end shift together).
  /// Defaults to true.
  final bool enableShift;

  /// Allow resizing from the start (top) handle.
  /// Defaults to true.
  final bool enableResizeStart;

  /// Allow resizing from the end (bottom) handle.
  /// Defaults to true.
  final bool enableResizeEnd;

  /// Allow horizontal drags (left/right = day change).
  /// When false, only vertical movement is permitted.
  /// Defaults to true.
  final bool enableHorizontalAxis;

  /// Allow vertical drags (up/down = time change).
  /// When false, only horizontal movement is permitted.
  /// Defaults to true.
  final bool enableVerticalAxis;

  // ── constraints ──────────────────────────────────────────────────────

  /// Shortest allowed slot duration in minutes.
  /// Resize handles will not let the slot shrink below this.
  /// Defaults to 15.
  final int minDurationMinutes;

  /// Maximum duration in minutes a timed slot may have.
  /// When null and the slot is a timed slot, the cap is one calendar
  /// day (1440 minutes).  When non-null the slot may span up to this
  /// many minutes, enabling multi-day slots.
  final int? maxDurationMinutes;

  // ── visuals ──────────────────────────────────────────────────────────

  /// Whether to show handle indicators (small pills at top/bottom).
  /// Defaults to true.
  final bool showHandles;

  /// Pixel height of the top and bottom resize handle zones.
  /// Defaults to 20.0.
  final double handleZoneSize;

  /// Minimum pointer movement in logical pixels before a drag commits.
  /// Prevents accidental micro-drags.  Defaults to 6.0.
  final double dragThreshold;

  /// Duration the user must hold before shift mode drag begins.
  /// Quick flings/swipes shorter than this pass through to the scroll
  /// views for calendar navigation.  Has no effect on resize handles.
  /// Defaults to 300 ms (standard long-press).
  final Duration longPressDuration;

  /// Accent colour for the slot border, fill, and handles.
  /// Falls back to the theme's secondary colour when null.
  final Color? accentColor;

  /// Border radius for the slot body.  Defaults to 8.0.
  final double slotBorderRadius;

  /// Whether to render default time/date labels inside the slot.
  /// Defaults to true.
  final bool showDefaultSlotText;

  /// Use 24-hour format for time labels (false = 12-hour AM/PM).
  /// Defaults to true.
  final bool use24HourFormat;

  /// Opacity applied to existing events whose time range overlaps this
  /// interactive slot.
  ///
  /// The interactive slot is an overlay and never participates in the event
  /// arranger, so existing events retain their normal width. Defaults to 0.4.
  final double overlappingEventOpacity;

  /// Whether the slot's start and end times are shown in the planner's time
  /// indicator column. Defaults to true.
  final bool showTimeIndicators;

  /// Colour of the slot start/end labels in the time indicator column.
  ///
  /// Falls back to [accentColor], then the theme's secondary colour.
  final Color? timeIndicatorColor;

  /// Optional text style for the slot start/end labels in the time indicator
  /// column. Its colour overrides [timeIndicatorColor] when supplied.
  final TextStyle? timeIndicatorTextStyle;

  // ── callbacks ────────────────────────────────────────────────────────

  /// Called whenever the slot model changes (created, updated, cleared).
  ///
  /// Passes null when the slot is dismissed (e.g. background tap with
  /// [clearWhenBackgroundTap] enabled).
  final void Function(CalendarSlot? slot)? onChanged;

  /// Called when the user taps an existing slot (without dragging).
  final void Function(CalendarSlot slot)? onTap;

  /// Called when a long-press begins on the slot.
  final void Function(CalendarSlot slot)? onLongPress;

  /// Called when a drag gesture begins on the slot, with the [DragMode]
  /// that was activated ([DragMode.shift], [DragMode.extendStart], or
  /// [DragMode.extendEnd]).
  final void Function(DragMode mode)? onDragStart;

  /// Called when a drag gesture ends.
  ///
  /// [mode] is the [DragMode] that was active during the drag,
  /// or null if the drag was cancelled abnormally.
  final void Function(DragMode? mode)? onDragEnd;

  // ── slot creation ────────────────────────────────────────────────────

  /// Enable interactive slot creation when tapping an empty area of a
  /// day column in the planner time-grid.
  ///
  /// Creates a [CalendarSlot] via [CalendarSlot.fromTap] with a duration
  /// given by [defaultDurationMinutes] (or 60 minutes if null).
  /// Defaults to false.
  final bool enableTapSlotSelection;

  /// Enable interactive slot creation when long-pressing an empty area
  /// of a day column in the planner time-grid.
  ///
  /// Same creation logic as [enableTapSlotSelection].
  /// Defaults to false.
  final bool enableLongPressSlotSelection;

  /// Enable interactive slot creation when double-tapping an empty area
  /// of a day column in the planner time-grid.
  ///
  /// Same creation logic as [enableTapSlotSelection].
  /// Defaults to false.
  final bool enableDoubleTapSlotSelection;

  /// Dismiss the current slot when the user taps on the planner
  /// background (outside the slot).  Defaults to true.
  final bool clearWhenBackgroundTap;

  /// Master switch for resize handles on the slot.
  ///
  /// When false, both [enableResizeStart] and [enableResizeEnd] are
  /// ignored and no resize handles appear.  Defaults to true.
  final bool enableResize;

  /// Default duration in minutes for newly created interactive slots.
  ///
  /// Receives the column index and the rounded tap date so the duration
  /// can vary by context.  When null (the default), falls back to
  /// [DayParam.defaultSlotDurationMinutes] (60 minutes).
  final int Function(int columnIndex, DateTime date)? defaultDurationMinutes;

  // ── builders ─────────────────────────────────────────────────────────

  /// Custom content widget rendered inside the default slot body.
  ///
  /// When null and [showDefaultSlotText] is true, a built-in time/date
  /// label is shown.  When null and [showDefaultSlotText] is false, only
  /// the coloured fill with border is shown.
  ///
  /// Replaces the legacy [SlotSelectionParam.slotSelectionContentBuilder].
  final Widget Function(CalendarSlot slot)? slotContentBuilder;

  /// Fully custom slot builder that replaces the entire default slot
  /// widget (including handles and decorations).
  ///
  /// When non-null, the default layout is skipped and this builder is
  /// used instead.  The [onChanged] callback must be called by the
  /// builder to keep the slot model in sync.
  ///
  /// Replaces the legacy [SlotSelectionParam.slotSelectionBuilder].
  // ignore: avoid_types_as_parameter_names
  final Widget Function(
    CalendarSlot slot,
    double dayWidth,
    dynamic dayParam,
    dynamic columnsParam,
    double heightPerMinute,
    void Function(CalendarSlot? updatedSlot) onChanged,
  )?
  slotBuilder;

  /// Custom widget for the top (start) resize handle indicator.
  ///
  /// When null and [showHandles] is true, a default pill-shaped handle
  /// is rendered.  Only shown when [enableResize] and [enableResizeStart]
  /// are both true.
  final Widget Function()? topHandleBuilder;

  /// Custom widget for the bottom (end) resize handle indicator.
  ///
  /// When null and [showHandles] is true, a default pill-shaped handle
  /// is rendered.  Only shown when [enableResize] and [enableResizeEnd]
  /// are both true.
  final Widget Function()? bottomHandleBuilder;
}
