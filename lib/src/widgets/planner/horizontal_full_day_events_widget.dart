import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../infinite_calendar_view.dart';
import '../../utils/extension.dart';
import '../../utils/list/infinite_list.dart';
import '../../utils/list/models/alignments.dart';

class HorizontalFullDayEventsWidget extends StatefulWidget {
  const HorizontalFullDayEventsWidget({
    super.key,
    required this.controller,
    this.textDirection = TextDirection.ltr,
    required this.fullDayParam,
    required this.columnsParam,
    required this.cellGapWidthPadding,
    required this.dayHorizontalController,
    required this.maxPreviousDays,
    required this.maxNextDays,
    required this.initialDate,
    required this.dayWidth,
    required this.todayColor,
    required this.timesIndicatorsWidth,
  });

  final EventsController controller;
  final TextDirection textDirection;
  final FullDayParam fullDayParam;
  final ColumnsParam columnsParam;
  final double cellGapWidthPadding;
  final ScrollController dayHorizontalController;
  final int? maxPreviousDays;
  final int? maxNextDays;
  final DateTime initialDate;
  final double dayWidth;
  final Color? todayColor;
  final double timesIndicatorsWidth;

  DateTime getDayFromIndex(int index) {
    return initialDate
        .addCalendarDays(textDirection == TextDirection.ltr ? index : -index);
  }

  @override
  State<HorizontalFullDayEventsWidget> createState() =>
      _HorizontalFullDayEventsWidgetState();
}

class _HorizontalFullDayEventsWidgetState
    extends State<HorizontalFullDayEventsWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullDayParam = widget.fullDayParam;
    final columnsParam = widget.columnsParam;
    final controller = widget.controller;
    final textDirection = widget.textDirection;
    final timesIndicatorsWidth = widget.timesIndicatorsWidth;
    final dayWidth = widget.dayWidth;
    final cellGapWidthPadding = widget.cellGapWidthPadding;
    final maxPreviousDays = widget.maxPreviousDays;
    final maxNextDays = widget.maxNextDays;
    final dayHorizontalController = widget.dayHorizontalController;

    return Container(
      decoration: fullDayParam.fullDayEventsBarDecoration,
      child: Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: timesIndicatorsWidth,
            height: fullDayParam.fullDayEventsBarHeight,
            child: fullDayParam.fullDayEventsBarLeftWidget ??
                Center(
                  child: Text(
                    fullDayParam.fullDayEventsBarLeftText,
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ),
          Expanded(
            child: SizedBox(
              height: fullDayParam.fullDayEventsBarHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Per-day backgrounds and single-day full-day events
                  InfiniteList(
                    controller: dayHorizontalController,
                    physics: const NeverScrollableScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    direction: InfiniteListDirection.multi,
                    negChildCount: maxPreviousDays,
                    posChildCount: maxNextDays,
                    builder: (context, index) {
                      var day = widget.getDayFromIndex(index);
                      var isToday = DateUtils.isSameDay(day, DateTime.now());
                      return InfiniteListItem(
                        contentBuilder: (context) {
                          return SizedBox(
                            width: dayWidth,
                            child: FullDayEventsWidget(
                              controller: controller,
                              isToday: isToday,
                              day: day,
                              todayColor: widget.todayColor,
                              fullDayParam: fullDayParam,
                              columnsParam: columnsParam,
                              dayWidth: dayWidth,
                              cellGapWidthPadding:
                                  cellGapWidthPadding,
                            ),
                          );
                        },
                      );
                    },
                  ),
                  // Full-day events overlay — rendered outside the per-day
                  // InfiniteList so multi-day events span day boundaries.
                  // Positioned.fill gives the child fixed constraints from
                  // the Stack size, so LayoutBuilder inside is safe.
                  if (fullDayParam.fullDayEventsBuilder == null)
                    Positioned.fill(
                      child: MultiDayEventsOverlay(
                      controller: controller,
                      scrollController: dayHorizontalController,
                      fullDayParam: fullDayParam,
                      dayWidth: dayWidth,
                      cellGapWidthPadding: cellGapWidthPadding,
                      getDayFromIndex: widget.getDayFromIndex,
                    ),
                    ),
                  // All-day slot selection overlay — a pill that appears
                  // when the user taps or long-presses a day cell in the
                  // all-day bar.  Styled to match InteractiveSlot.
                  _buildAllDaySlotOverlay(controller, columnsParam,
                      fullDayParam, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // All-day slot selection overlay
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAllDaySlotOverlay(
    EventsController controller,
    ColumnsParam columnsParam,
    FullDayParam fullDayParam,
    ThemeData theme,
  ) {
    final param = fullDayParam.allDaySlotSelectionParam;
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller.allDaySlotSelectionNotifier,
        widget.dayHorizontalController,
      ]),
      builder: (context, _) {
        final selection = controller.allDaySlotSelectionNotifier.value;
        if (selection == null) return const SizedBox.shrink();

        final dayWidth = widget.dayWidth;
        final pad = widget.cellGapWidthPadding;
        final eventEndGap = fullDayParam.eventEndGap;
        final eventHeight = fullDayParam.fullDayEventHeight;
        const rowPadding = 2.0;

        if (!widget.dayHorizontalController.hasClients) {
          return const SizedBox.shrink();
        }
        final scrollOffset = widget.dayHorizontalController.offset;

        // Compute the start day index from initialDate.
        final startDiff = selection.startDate.withoutTime
            .difference(widget.initialDate.withoutTime)
            .inDays;
        final startIndex = widget.textDirection == TextDirection.rtl
            ? -startDiff
            : startDiff;
        final daysSpan = selection.dayCount;

        // Column offset within the day cell.
        final innerWidth = dayWidth - pad * 2;
        final columnPositions =
            columnsParam.getColumPositions(innerWidth, selection.columnIndex);

        // Natural left edge (before clamping).
        final naturalLeft =
            startIndex * dayWidth - scrollOffset + pad + columnPositions[0];
        final naturalWidth = columnPositions[1] -
            columnPositions[0] -
            eventEndGap;

        // Apply sticky-left for multi-day selections, matching the
        // MultiDayEventsOverlay behaviour.
        final double left;
        final double width;
        if (daysSpan > 1 && naturalLeft < 0) {
          final minWidth =
              (columnPositions[1] - columnPositions[0]) - eventEndGap;
          final naturalRight = naturalLeft + naturalWidth;
          if (naturalRight >= minWidth) {
            left = 0.0;
            width = (naturalRight - left).clamp(minWidth, naturalWidth);
          } else {
            left = naturalRight - minWidth;
            width = minWidth;
          }
        } else {
          left = naturalLeft;
          width = naturalWidth;
        }

        // Visibility culling.
        final viewportWidth =
            MediaQuery.of(context).size.width - widget.timesIndicatorsWidth;
        if (naturalLeft + naturalWidth <= 0 || naturalLeft >= viewportWidth) {
          return const SizedBox.shrink();
        }

        final accent =
            param.accentColor ?? theme.colorScheme.secondary;

        return Positioned(
          left: left,
          top: rowPadding,
          width: width,
          height: eventHeight,
          child: param.slotSelectionContentBuilder?.call(selection) ??
              _AllDaySlotBody(
                accent: accent,
                borderRadius: param.slotBorderRadius,
                selection: selection,
                showText: param.showDefaultSlotText,
              ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _AllDaySlotBody — matches the visual styling of InteractiveSlot's
// _SlotBody.  Used as the default content for the all-day slot selection pill.
// ═══════════════════════════════════════════════════════════════════════════

class _AllDaySlotBody extends StatelessWidget {
  const _AllDaySlotBody({
    required this.accent,
    required this.borderRadius,
    required this.selection,
    required this.showText,
  });

  final Color accent;
  final double borderRadius;
  final AllDaySlotSelection selection;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final fillColor = accent.withAlpha(30);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: showText
          ? Center(
              child: Text(
                _formatDate(selection.startDate),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                      fontSize: 11,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : const SizedBox.expand(),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

/// Overlay that renders ALL full-day events (single-day and multi-day) with
/// a unified greedy row-assignment algorithm so nothing overlaps. Multi-day
/// events span across day boundaries. Must be placed inside a [Positioned.fill]
/// so the [LayoutBuilder] inside receives fixed constraints from the [Stack]
/// size — those never change on scroll, so no layout churn occurs.
class MultiDayEventsOverlay extends StatefulWidget {
  const MultiDayEventsOverlay({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.fullDayParam,
    required this.dayWidth,
    required this.cellGapWidthPadding,
    required this.getDayFromIndex,
  });

  final EventsController controller;
  final ScrollController scrollController;
  final FullDayParam fullDayParam;
  final double dayWidth;
  final double cellGapWidthPadding;
  final DateTime Function(int index) getDayFromIndex;

  @override
  State<MultiDayEventsOverlay> createState() => _MultiDayEventsOverlayState();
}

class _MultiDayEventsOverlayState extends State<MultiDayEventsOverlay> {
  late VoidCallback _scrollListener;
  late VoidCallback _eventsListener;

  @override
  void initState() {
    super.initState();
    _scrollListener = () {
      if (mounted) setState(() {});
    };
    _eventsListener = () {
      if (mounted) setState(() {});
    };
    widget.scrollController.addListener(_scrollListener);
    widget.controller.addListener(_eventsListener);
  }

  @override
  void didUpdateWidget(MultiDayEventsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scrollListener);
      widget.scrollController.addListener(_scrollListener);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_eventsListener);
      widget.controller.addListener(_eventsListener);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrollListener);
    widget.controller.removeListener(_eventsListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.scrollController.hasClients) return const SizedBox.shrink();
    // LayoutBuilder is safe here because we are inside Positioned.fill whose
    // constraints come from the fixed-size Stack parent — they never change
    // on scroll, so no layout churn occurs.
    return LayoutBuilder(builder: (context, constraints) {
      return _buildOverlay(constraints.maxWidth);
    });
  }

  Widget _buildOverlay(double viewportWidth) {
    if (!widget.scrollController.hasClients) return const SizedBox.shrink();

    final offset = widget.scrollController.positions.first.pixels;
    final pad = widget.cellGapWidthPadding;
    final eventHeight = widget.fullDayParam.fullDayEventHeight;
    const rowPadding = 2.0;
    const lookback = 90;

    final firstVisibleIndex = (offset / widget.dayWidth).floor();
    final lastVisibleIndex =
        firstVisibleIndex + (viewportWidth / widget.dayWidth).ceil() + 1;

    // Collect all full-day events.
    // Multi-day: only daysIndex==0 (first segment), from lookback window.
    // Single-day: visible range only.
    final Map<UniqueKey, Event> eventByKey = {};
    final Map<UniqueKey, int> startIndexByKey = {};

    for (int i = firstVisibleIndex - lookback; i <= lastVisibleIndex; i++) {
      final day = widget.getDayFromIndex(i);
      final dayEvents = widget.controller.getFilteredDayEvents(
        day,
        returnDayEvents: false,
        returnMultiDayEvents: widget.fullDayParam.showMultiDayEvents,
      );
      for (final e in dayEvents ?? []) {
        if (e.isMultiDay) {
          if ((e.daysIndex ?? 0) != 0) continue;
          if (!eventByKey.containsKey(e.uniqueId)) {
            eventByKey[e.uniqueId] = e;
            startIndexByKey[e.uniqueId] = i;
          }
        } else {
          if (i < firstVisibleIndex || i > lastVisibleIndex) continue;
          eventByKey[e.uniqueId] = e;
          startIndexByKey[e.uniqueId] = i;
        }
      }
    }

    if (eventByKey.isEmpty) return const SizedBox.shrink();

    // Compute day spans before sorting so the sort can use span as a
    // tiebreaker (longer / multi-day events first for stable row assignment).
    final Map<UniqueKey, int> spanByKey = {};
    for (final key in eventByKey.keys) {
      final e = eventByKey[key]!;
      int daysSpan = 1;
      if (e.isMultiDay && e.effectiveEndTime != null) {
        final endDay = DateTime(e.effectiveEndTime!.year,
            e.effectiveEndTime!.month, e.effectiveEndTime!.day);
        final startDay =
            DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
        daysSpan = endDay.difference(startDay).inDays + 1;
      }
      spanByKey[key] = daysSpan;
    }

    // Sort by start time, then longest span first.
    // This ensures multi-day events always precede same-start single-day
    // events, producing stable row assignment as the viewport scrolls.
    final keys = eventByKey.keys.toList()
      ..sort((a, b) {
        final timeComp =
            eventByKey[a]!.startTime.compareTo(eventByKey[b]!.startTime);
        if (timeComp != 0) return timeComp;
        return (spanByKey[b] ?? 1).compareTo(spanByKey[a] ?? 1); // longer first
      });

    // Greedy row assignment: first available row with no overlap.
    final Map<UniqueKey, int> rowByKey = {};
    final List<int> rowLastOccupied = [];
    for (final key in keys) {
      final startIndex = startIndexByKey[key]!;
      final endIndex = startIndex + spanByKey[key]! - 1;
      int r = 0;
      while (r < rowLastOccupied.length &&
          rowLastOccupied[r] >= startIndex) {
        r++;
      }
      rowLastOccupied.length <= r
          ? rowLastOccupied.add(endIndex)
          : rowLastOccupied[r] = endIndex;
      rowByKey[key] = r;
    }

    final List<Widget> positioned = [];
    for (final key in keys) {
      final event = eventByKey[key]!;
      final startIndex = startIndexByKey[key]!;
      final daysSpan = spanByKey[key]!;
      final row = rowByKey[key]!;

      final int endIndex = startIndex + daysSpan - 1;

      final double naturalLeft = startIndex * widget.dayWidth - offset + pad;
      final double naturalWidth = widget.dayWidth * daysSpan - pad * 2 - widget.fullDayParam.eventEndGap;
      final double naturalRight = naturalLeft + naturalWidth;

      // Visibility skip: use index-based logic for multi-day events so that
      // scroll-physics overshoot (which corrupts floating-point pixel values)
      // never causes a ghost render. Single-day events use pixel math since
      // they have no sticky-clamp behaviour and never span the viewport.
      if (daysSpan > 1) {
        if (endIndex < firstVisibleIndex) continue;   // all days off-screen left
        if (startIndex > lastVisibleIndex) continue;  // all days off-screen right
        if (naturalRight <= 0) continue;              // last day clipped off left
      } else {
        if (naturalRight <= 0 || naturalLeft >= viewportWidth) continue;
      }

      // For multi-day events: apply left-sticky behaviour as soon as the
      // natural left edge scrolls off-screen, not only after the next whole day
      // becomes the first visible index. Keep at least one day of width so the
      // event contents are never squashed during the final-day exit.
      final double left;
      final double width;
      if (daysSpan > 1 && naturalLeft < 0) {
        final minWidth = widget.dayWidth - pad * 2 - widget.fullDayParam.eventEndGap;
        if (naturalRight >= minWidth) {
          left = 0.0;
          width = (naturalRight - left).clamp(minWidth, naturalWidth).toDouble();
        } else {
          // Keep a one-day event shape and let it scroll off with its true end.
          left = naturalRight - minWidth;
          width = minWidth;
        }
      } else {
        left = naturalLeft;
        width = naturalWidth;
      }

      final double top = rowPadding + row * (eventHeight + rowPadding);

      positioned.add(Positioned(
        left: left,
        top: top,
        width: width,
        height: eventHeight,
        child: widget.fullDayParam.fullDayEventBuilder?.call(event, width) ??
            DefaultDayEvent(
              height: eventHeight,
              width: width,
              title: event.title,
              titleFontSize: 10,
              description: event.description,
              color: event.color,
              textColor: event.textColor,
            ),
      ));
    }

    if (positioned.isEmpty) return const SizedBox.shrink();
    return Stack(clipBehavior: Clip.hardEdge, children: positioned);
  }
}

class FullDayEventsWidget extends StatefulWidget {
  const FullDayEventsWidget({
    super.key,
    required this.controller,
    required this.isToday,
    required this.day,
    required this.todayColor,
    required this.fullDayParam,
    required this.columnsParam,
    required this.dayWidth,
    required this.cellGapWidthPadding,
  });

  final EventsController controller;
  final bool isToday;
  final DateTime day;
  final Color? todayColor;
  final FullDayParam fullDayParam;
  final ColumnsParam columnsParam;
  final double dayWidth;
  final double cellGapWidthPadding;

  @override
  State<FullDayEventsWidget> createState() => _FullDayEventsWidgetState();
}

class _FullDayEventsWidgetState extends State<FullDayEventsWidget> {
  List<Event>? events;

  late VoidCallback eventListener;

  @override
  void initState() {
    super.initState();
    eventListener = () => updateEvents();
    widget.controller.addListener(eventListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      updateEvents();
    });
  }

  @override
  void dispose() {
    super.dispose();
    widget.controller.removeListener(eventListener);
  }

  void updateEvents() {
    // Events are rendered by MultiDayEventsOverlay; nothing to update here.
  }

  @override
  Widget build(BuildContext context) {
    final param = widget.fullDayParam.allDaySlotSelectionParam;
    final canInteract =
        param.enableTapSlotSelection || param.enableLongPressSlotSelection;
    final width = widget.dayWidth - (widget.cellGapWidthPadding * 2);

    // Only render the background colour and optional column dividers.
    // All events are rendered by MultiDayEventsOverlay.
    final child = Padding(
      padding:
          EdgeInsets.symmetric(horizontal: widget.cellGapWidthPadding),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isToday && widget.todayColor != null
              ? widget.todayColor
              : widget.fullDayParam.fullDayBackgroundColor,
        ),
        child: widget.columnsParam.columns > 1
            ? getColumnPainter(width)
            : null,
      ),
    );

    if (!canInteract) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: param.enableTapSlotSelection
          ? (details) => _onAllDayTap(details, width)
          : null,
      onLongPressStart: param.enableLongPressSlotSelection
          ? (details) => _onAllDayTap(details, width, isLongPress: true)
          : null,
      child: child,
    );
  }

  void _onAllDayTap(dynamic details, double innerWidth, {bool isLongPress = false}) {
    final param = widget.fullDayParam.allDaySlotSelectionParam;

    // Determine which column was tapped.
    int column = 0;
    if (details is TapUpDetails) {
      column = widget.columnsParam.getColumnIndex(innerWidth, details.localPosition.dx);
    } else if (details is LongPressStartDetails) {
      column = widget.columnsParam.getColumnIndex(innerWidth, details.localPosition.dx);
    }

    final day = widget.day.withoutTime;
    final selection = AllDaySlotSelection(column, day, day, day);

    widget.controller.allDaySlotSelectionNotifier.value = selection;
    // Clear any timed slot selection when creating an all-day slot.
    widget.controller.slotSelectionNotifier.value = null;

    if (isLongPress) {
      param.onSlotSelectionLongPress?.call(selection);
    } else {
      param.onSlotSelectionTap?.call(selection);
    }
    param.onSlotSelectionChange?.call(selection);
  }

  Widget getColumnPainter(double width) {
    return SizedBox(
      width: width,
      height: widget.fullDayParam.fullDayEventsBarHeight,
      child: CustomPaint(
        foregroundPainter: widget.columnsParam.columnCustomPainter
                ?.call(width, widget.columnsParam.columns) ??
            ColumnPainter(
              width: width,
              columnsParam: widget.columnsParam,
              lineColor: Theme.of(context).colorScheme.outlineVariant,
            ),
      ),
    );
  }
}
