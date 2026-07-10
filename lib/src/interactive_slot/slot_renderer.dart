import 'package:flutter/material.dart';

import 'slot_config.dart';
import 'slot_selection.dart';

/// Renders the visual body of an interactive slot.
///
/// Handles three rendering modes:
/// * **Single-day timed** — a vertical rounded rectangle with time labels.
/// * **Multi-day timed** — per-day segments with connected borders.
/// * **All-day** — a horizontal pill with date labels.
///
/// This widget is purely visual — it contains NO gesture recognizers.
/// Gestures are handled by [SlotHandleZone] wrappers.
class SlotRenderer extends StatelessWidget {
  const SlotRenderer({
    super.key,
    required this.slot,
    required this.config,
    this.accentColor,
    this.isDragging = false,
    this.hideLeftBorder = false,
    this.hideRightBorder = false,
    this.hideLeftHandle,
    this.hideRightHandle,
  });

  final CalendarSlot slot;
  final SlotInteractionConfig config;
  final Color? accentColor;
  final bool isDragging;

  /// When true, the left border and left radius are suppressed (all-day
  /// pills only).  Set when the slot's start date is off-screen left,
  /// indicating an "ongoing" event.
  final bool hideLeftBorder;

  /// When true, the right border and right radius are suppressed (all-day
  /// pills only).  Set when the slot's end date is off-screen right,
  /// indicating an "ongoing" event.
  final bool hideRightBorder;

  /// When provided, controls date-label padding independently from the
  /// all-day pill border state.
  final bool? hideLeftHandle;
  final bool? hideRightHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        accentColor ?? config.accentColor ?? theme.colorScheme.secondary;

    if (slot.isAllDay) {
      return _AllDayPill(
        accent: accent,
        borderRadius: config.slotBorderRadius,
        isDragging: isDragging,
        hideLeftBorder: hideLeftBorder,
        hideRightBorder: hideRightBorder,
        child: config.showDefaultSlotText
            ? _AllDayLabels(
                slot: slot,
                accent: accent,
                config: config,
                hideLeftHandle: hideLeftHandle ?? hideLeftBorder,
                hideRightHandle: hideRightHandle ?? hideRightBorder,
              )
            : null,
      );
    }

    if (slot.totalDaysSpanned > 1) {
      return _MultiDayBody(
        accent: accent,
        borderRadius: config.slotBorderRadius,
        isDragging: isDragging,
        slot: slot,
        config: config,
      );
    }

    return _SingleDayBody(
      accent: accent,
      borderRadius: config.slotBorderRadius,
      isDragging: isDragging,
      slot: slot,
      config: config,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SlotBody — filled rounded rectangle (shared by single/multi day).
// ═══════════════════════════════════════════════════════════════════════════

class _SlotBody extends StatelessWidget {
  const _SlotBody({
    required this.accent,
    required this.borderRadius,
    this.isDragging = false,
    this.child,
    this.hideTopBorder = false,
    this.hideBottomBorder = false,
  });

  final Color accent;
  final double borderRadius;
  final bool isDragging;
  final Widget? child;
  final bool hideTopBorder;
  final bool hideBottomBorder;

  @override
  Widget build(BuildContext context) {
    final fillColor = accent.withAlpha(30);
    final side = BorderSide(color: accent, width: 2);
    final none = BorderSide.none;

    final effectiveBorder = hideTopBorder || hideBottomBorder
        ? Border(
            left: side,
            right: side,
            top: hideTopBorder ? none : side,
            bottom: hideBottomBorder ? none : side,
          )
        : Border.all(color: accent, width: 2);

    final topRadius = hideTopBorder
        ? Radius.zero
        : Radius.circular(borderRadius);
    final bottomRadius = hideBottomBorder
        ? Radius.zero
        : Radius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        border: effectiveBorder,
        borderRadius: BorderRadius.vertical(
          top: topRadius,
          bottom: bottomRadius,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: accent.withAlpha(70),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: accent.withAlpha(25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SingleDayBody
// ═══════════════════════════════════════════════════════════════════════════

class _SingleDayBody extends StatelessWidget {
  const _SingleDayBody({
    required this.accent,
    required this.borderRadius,
    required this.isDragging,
    required this.slot,
    required this.config,
  });

  final Color accent;
  final double borderRadius;
  final bool isDragging;
  final CalendarSlot slot;
  final SlotInteractionConfig config;

  static const double _handlePadding = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handlesVisible = config.showHandles;

    final child = config.showDefaultSlotText
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              handlesVisible ? _handlePadding : 7,
              12,
              handlesVisible ? _handlePadding : 7,
            ),
            child: _TimeLabels(
              slot: slot,
              accent: accent,
              config: config,
              theme: theme,
            ),
          )
        : null;

    return _SlotBody(
      accent: accent,
      borderRadius: borderRadius,
      isDragging: isDragging,
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _MultiDayBody — per-day segments with connected borders.
// ═══════════════════════════════════════════════════════════════════════════

/// Renders one segment of a multi-day slot.
///
/// [hideTopBorder] and [hideBottomBorder] suppress the border on the
/// connecting edges between adjacent day segments so the slot looks
/// like one continuous block across columns.
///
/// [padTop] / [padBottom] reserve space for the resize handle zones
/// (fixed pixel values, not percentages).  Labels are inset accordingly
/// so they never overlap the drag handles.
class SegmentBody extends StatelessWidget {
  const SegmentBody({
    super.key,
    required this.accent,
    required this.borderRadius,
    required this.hideTopBorder,
    required this.hideBottomBorder,
    this.isDragging = false,
    this.padTop = 0,
    this.padBottom = 0,
    this.showStartLabel = false,
    this.showEndLabel = false,
    this.startTime,
    this.endTime,
    this.use24HourFormat = true,
    this.child,
  });

  final Color accent;
  final double borderRadius;
  final bool hideTopBorder;
  final bool hideBottomBorder;
  final bool isDragging;
  final double padTop;
  final double padBottom;
  final bool showStartLabel;
  final bool showEndLabel;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool use24HourFormat;
  final Widget? child;

  /// Below this pixel height (after subtracting handle pads), hide
  /// the end label to avoid overflow.
  static const double _compactHeight = 60.0;

  /// Below this pixel height, hide all text.
  static const double _minTextHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? labelChild;
    if (showStartLabel || showEndLabel) {
      labelChild = LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final usableH = h - padTop - padBottom;
          if (usableH < _minTextHeight) return const SizedBox.shrink();
          final compact = usableH < _compactHeight;

          String fmt(DateTime dt) {
            final hour = dt.hour;
            final min = dt.minute.toString().padLeft(2, '0');
            if (use24HourFormat) {
              return '${hour.toString().padLeft(2, '0')}:$min';
            }
            final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
            final period = hour >= 12 ? 'pm' : 'am';
            return '$h12:$min $period';
          }

          return Padding(
            padding: EdgeInsets.only(
              top: padTop,
              bottom: padBottom,
              left: 4,
              right: 4,
            ),
            child: Column(
              children: [
                if (showStartLabel && startTime != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      fmt(startTime!),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (!compact) const Spacer(),
                if (showEndLabel && !compact && endTime != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      fmt(endTime!),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: accent,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    return _SlotBody(
      accent: accent,
      borderRadius: borderRadius,
      isDragging: isDragging,
      hideTopBorder: hideTopBorder,
      hideBottomBorder: hideBottomBorder,
      child: labelChild ?? child,
    );
  }
}

class _MultiDayBody extends StatelessWidget {
  const _MultiDayBody({
    required this.accent,
    required this.borderRadius,
    required this.isDragging,
    required this.slot,
    required this.config,
  });

  final Color accent;
  final double borderRadius;
  final bool isDragging;
  final CalendarSlot slot;
  final SlotInteractionConfig config;

  @override
  Widget build(BuildContext context) {
    // Multi-day timed slots render as a single continuous filled area.
    // Per-segment borders are handled by the overlay positioning.
    return _SlotBody(
      accent: accent,
      borderRadius: borderRadius,
      isDragging: isDragging,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AllDayPill — horizontal pill for all-day slots.
// ═══════════════════════════════════════════════════════════════════════════

class _AllDayPill extends StatelessWidget {
  const _AllDayPill({
    required this.accent,
    required this.borderRadius,
    this.isDragging = false,
    this.child,
    this.hideLeftBorder = false,
    this.hideRightBorder = false,
  });

  final Color accent;
  final double borderRadius;
  final bool isDragging;
  final Widget? child;
  final bool hideLeftBorder;
  final bool hideRightBorder;

  @override
  Widget build(BuildContext context) {
    final fillColor = accent.withAlpha(30);
    final side = BorderSide(color: accent, width: 2);
    final none = BorderSide.none;

    // When a side is off-screen, suppress its border and radius to
    // indicate the event is "ongoing" beyond the visible viewport.
    final effectiveBorder = (hideLeftBorder || hideRightBorder)
        ? Border(
            top: side,
            bottom: side,
            left: hideLeftBorder ? none : side,
            right: hideRightBorder ? none : side,
          )
        : Border.all(color: accent, width: 2);

    final topLeft = hideLeftBorder
        ? Radius.zero
        : Radius.circular(borderRadius);
    final topRight = hideRightBorder
        ? Radius.zero
        : Radius.circular(borderRadius);
    final bottomLeft = hideLeftBorder
        ? Radius.zero
        : Radius.circular(borderRadius);
    final bottomRight = hideRightBorder
        ? Radius.zero
        : Radius.circular(borderRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        border: effectiveBorder,
        borderRadius: BorderRadius.only(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: accent.withAlpha(70),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: accent.withAlpha(25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: child ?? const SizedBox.expand(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _TimeLabels — start/end time labels for timed slots.
// ═══════════════════════════════════════════════════════════════════════════

class _TimeLabels extends StatelessWidget {
  const _TimeLabels({
    required this.slot,
    required this.accent,
    required this.config,
    required this.theme,
  });

  final CalendarSlot slot;
  final Color accent;
  final SlotInteractionConfig config;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final startText = _formatTime(slot.startDateTime, config.use24HourFormat);
    final endText = _formatTime(slot.endDateTime, config.use24HourFormat);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            startText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
              fontSize: 12,
            ),
          ),
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            endText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTime(DateTime dt, bool use24Hour) {
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    if (use24Hour) {
      return '${hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour >= 12 ? 'pm' : 'am';
    return '$hour12:$minute $period';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AllDayLabels — date labels for all-day slot pills.
// ═══════════════════════════════════════════════════════════════════════════

class _AllDayLabels extends StatelessWidget {
  const _AllDayLabels({
    required this.slot,
    required this.accent,
    required this.config,
    this.hideLeftHandle = false,
    this.hideRightHandle = false,
  });

  final CalendarSlot slot;
  final Color accent;
  final SlotInteractionConfig config;

  /// When true, the left handle is not visible (start off-screen) so
  /// no extra padding is needed on that side.
  final bool hideLeftHandle;

  /// When true, the right handle is not visible (end off-screen) so
  /// no extra padding is needed on that side.
  final bool hideRightHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSingleDay = slot.totalDaysSpanned == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 60) return const SizedBox.shrink();

        // Shift text inward when resize handles are visible so labels
        // don't overlap the handle pills. Skip when the handle is hidden
        // because that side is off-screen.
        final handlePad = config.handleZoneSize;
        final leftPad =
            config.enableResizeStart && config.showHandles && !hideLeftHandle
            ? handlePad
            : 4.0;
        final rightPad =
            config.enableResizeEnd && config.showHandles && !hideRightHandle
            ? handlePad
            : 4.0;

        if (isSingleDay || constraints.maxWidth < 100) {
          return Padding(
            padding: EdgeInsets.fromLTRB(leftPad, 0, rightPad, 0),
            child: Center(
              child: Text(
                _formatDate(slot.startDateTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: accent,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(leftPad, 0, rightPad, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formatDate(slot.startDateTime),
                  textAlign: .start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accent,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Text(
                  _formatDate(
                    slot.endDateTime.subtract(const Duration(days: 1)),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accent,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
