import 'dart:ui';

import 'slot_selection.dart';

/// Configuration for the interactive slot drag/resize system.
///
/// Pass an instance to [SlotOverlay] or set on the planner's [DayParam]
/// (future: [SlotSelectionParam]) to control which interactions are
/// available and how they behave.
class SlotInteractionConfig {
  const SlotInteractionConfig({
    this.stepMinutes = 15,
    this.enableShift = true,
    this.enableExtendStart = true,
    this.enableExtendEnd = true,
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
    this.onChanged,
    this.onTap,
    this.onLongPress,
    this.onDragStart,
    this.onDragEnd,
  });

  // ── drag behaviour ───────────────────────────────────────────────────

  /// Snap increment in minutes for timed-slot drag/resize operations.
  /// Defaults to 15 minutes.
  final int stepMinutes;

  /// Allow moving the entire slot (both start and end shift together).
  /// Defaults to true.
  final bool enableShift;

  /// Allow resizing from the start (top) handle.
  /// Defaults to true.
  final bool enableExtendStart;

  /// Allow resizing from the end (bottom) handle.
  /// Defaults to true.
  final bool enableExtendEnd;

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
  /// When null, defaults to 2 days (2880 minutes).
  /// Set to a specific value to cap slot duration directly.
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

  // ── callbacks ────────────────────────────────────────────────────────

  /// Called whenever the slot model changes (created, updated, cleared).
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
}
