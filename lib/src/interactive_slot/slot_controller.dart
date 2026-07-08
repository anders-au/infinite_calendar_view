
import 'dart:async' as async;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'slot_config.dart';
import 'slot_constraints.dart';
import 'slot_selection.dart';

/// Manages the lifecycle of a single drag interaction on a slot.
///
/// Created when the user begins a drag gesture (pointer moves past the
/// drag threshold) and destroyed when the gesture ends (pointer up or
/// cancelled).  Maintains an immutable [anchor] snapshot and accumulated
/// pixel delta to compute validated slot updates.
///
/// The core loop (called on every pointer-move event):
/// ```dart
/// session.addDelta(details.delta);
/// final proposed = session.computeProposed();
/// final clamped = SlotConstraints.clamp(proposed, session);
/// if (clamped != session.lastEmitted) emit(clamped);
/// ```
class DragSession {
  DragSession({
    required this.anchor,
    required this.mode,
    required this.config,
    required this.dayWidth,
    required this.heightPerMinute,
  });

  // ── immutable anchor ─────────────────────────────────────────────────
  /// The slot state at the moment the drag began.  Never changes.
  final CalendarSlot anchor;

  /// The drag mode (shift / extendStart / extendEnd).
  final DragMode mode;

  /// Active configuration for this drag session.
  final SlotInteractionConfig config;

  /// Pixel width of one day column.
  final double dayWidth;

  /// Pixels-per-minute for vertical conversion.
  final double heightPerMinute;

  // ── mutable drag state ───────────────────────────────────────────────
  Offset _accumulatedDelta = Offset.zero;
  CalendarSlot? _lastEmitted;

  /// The last slot value that was emitted to listeners.
  /// Null until the first emission.
  CalendarSlot? get lastEmitted => _lastEmitted;

  /// Total pixel offset accumulated since drag start.
  Offset get accumulatedDelta => _accumulatedDelta;

  // ── mutation ─────────────────────────────────────────────────────────

  /// Adds [delta] (a raw pointer-move delta from [DragUpdateDetails]) to
  /// the accumulated total.
  void addDelta(Offset delta) {
    _accumulatedDelta += delta;
  }

  /// Computes the proposed slot by applying the accumulated delta to the
  /// anchor, then clamps it via [SlotConstraints].
  ///
  /// Returns the clamped slot, or null if the slot hasn't meaningfully
  /// changed from the anchor (e.g. zero delta on first move).
  CalendarSlot? computeProposed() {
    final proposed = anchor.applyDelta(
      _accumulatedDelta,
      config: config,
      mode: mode,
      dayWidth: dayWidth,
      heightPerMinute: heightPerMinute,
    );

    final clamped = SlotConstraints.clamp(
      proposed: proposed,
      anchor: anchor,
      mode: mode,
      config: config,
    );

    return clamped;
  }

  /// Convenience: adds [delta], computes and clamps the proposal, and if
  /// the result differs from [lastEmitted], returns it (and caches it).
  ///
  /// Returns null when nothing changed (the slot is at a constraint
  /// boundary or the delta was too small to snap to a new step).
  CalendarSlot? applyUpdate(Offset delta) {
    addDelta(delta);
    final clamped = computeProposed();
    if (clamped == null) return null;

    if (_lastEmitted != null && clamped == _lastEmitted) return null;

    if (debugSlotDrag) {
      debugPrint('[DragSession] applyUpdate  '
          'mode=$mode  '
          'accumDx=${_accumulatedDelta.dx.toStringAsFixed(1)}  '
          'accumDy=${_accumulatedDelta.dy.toStringAsFixed(1)}  '
          'anchorStart=${anchor.startDateTime.toIso8601String()}  '
          'anchorEnd=${anchor.endDateTime.toIso8601String()}  '
          'anchorDays=${anchor.totalDaysSpanned}  '
          'clampedStart=${clamped.startDateTime.toIso8601String()}  '
          'clampedEnd=${clamped.endDateTime.toIso8601String()}  '
          'clampedDays=${clamped.totalDaysSpanned}  '
          'clampedDur=${clamped.durationInMinutes}min');
    }

    _lastEmitted = clamped;
    return clamped;
  }

  /// Resets the session to its initial state (anchor only).
  void reset() {
    _accumulatedDelta = Offset.zero;
    _lastEmitted = null;
  }
}

/// Auto-scrolls the planner's scroll controllers when the pointer is near
/// the viewport edge during a drag.  Uses an internal periodic async.Timer so
/// scrolling continues smoothly even when the finger pauses at the edge.
class SlotAutoScroller {
  /// Set to `true` to print auto-scroll diagnostics to the console.
  static bool debugAutoScroll = false;

  /// Shared viewport-bounds detection usable from both slot overlays
  /// and external callers like [DayWidget].
  ///
  /// Walks up the render tree from [context] to find the planner viewport
  /// [RenderBox] and returns its global bounds, excluding the given insets
  /// (typically the time-indicator column width).
  ///
  /// Falls back to the screen size (minus safe areas) if no suitable
  /// ancestor is found.
  static Rect? viewportBoundsOf(BuildContext context, {double leftInset = 0, double rightInset = 0}) {
    // Start from the parent so the calling widget's own RenderBox is
    // never mistaken for the viewport.
    RenderObject? current = context.findRenderObject();
    if (current != null) {
      final parent = current.parent;
      current = parent is RenderObject ? parent : null;
    }
    RenderBox? best;
    double bestTop = double.negativeInfinity;

    double screenHeight;
    try {
      screenHeight = MediaQuery.sizeOf(context).height;
    } catch (_) {
      screenHeight = double.infinity;
    }

    while (current != null) {
      if (current is RenderBox && current.hasSize) {
        final size = current.size;
        if (size.width >= 200 && size.height >= 200 && size.height <= screenHeight) {
          try {
            final globalTop = current.localToGlobal(Offset.zero).dy;
            if (globalTop > bestTop) {
              bestTop = globalTop;
              best = current;
            }
          } catch (_) {
            // Transform might be unavailable — keep walking.
          }
        }
      }
      final parent = current.parent;
      if (parent is RenderObject) {
        current = parent;
      } else {
        break;
      }
    }

    if (best != null) {
      try {
        final globalOffset = best.localToGlobal(Offset.zero);
        if (debugAutoScroll) {
          debugPrint(
            '[autoScroll] selected viewport: '
            'type=${best.runtimeType} '
            'size=${best.size.width.toStringAsFixed(0)}x${best.size.height.toStringAsFixed(0)} '
            'global=(${globalOffset.dx.toStringAsFixed(0)},${globalOffset.dy.toStringAsFixed(0)}) '
            'insetL=${leftInset.toStringAsFixed(0)} '
            'insetR=${rightInset.toStringAsFixed(0)}',
          );
        }
        return Rect.fromLTWH(globalOffset.dx + leftInset, globalOffset.dy, best.size.width - leftInset - rightInset, best.size.height);
      } catch (_) {}
    }

    // Fallback: use the screen dimensions from MediaQuery.
    try {
      final mediaQuery = MediaQuery.of(context);
      final padding = mediaQuery.padding;
      return Rect.fromLTWH(
        padding.left + leftInset,
        padding.top,
        mediaQuery.size.width - padding.left - padding.right - leftInset - rightInset,
        mediaQuery.size.height - padding.top - padding.bottom,
      );
    } catch (_) {
      return null;
    }
  }

  SlotAutoScroller({
    this.verticalScrollController,
    this.horizontalScrollController,
    this.autoScrollThreshold = 40.0,
    this.autoScrollMaxSpeed = 8.0,
    this.viewportLeftInset = 0,
    this.viewportRightInset = 0,
    this.onScroll,
  });

  final ScrollController? verticalScrollController;
  final ScrollController? horizontalScrollController;
  final double autoScrollThreshold;
  final double autoScrollMaxSpeed;
  final double viewportLeftInset;
  final double viewportRightInset;

  /// Called with the actual scroll delta applied, so the drag session
  /// can compensate its accumulated delta to keep the slot under the finger.
  final void Function(Offset scrollDelta)? onScroll;

  Offset _lastGlobalPosition = Offset.zero;
  async.Timer? _timer;
  Rect? _bounds;

  /// Call this on every drag-update with the current pointer position
  /// and viewport bounds.  Starts/stops the periodic scroll async.Timer as needed.
  void update(Offset globalPosition, Rect viewportBounds) {
    _lastGlobalPosition = globalPosition;
    _bounds = viewportBounds;

    final nearEdge = _isNearEdge(globalPosition, viewportBounds);
    if (nearEdge && _timer == null) {
      _timer = async.Timer.periodic(const Duration(milliseconds: 16), _onTick);
    } else if (!nearEdge && _timer != null) {
      _stopTimer();
    }
  }

  void _onTick(async.Timer t) {
    if (_bounds == null) return;
    final delta = _applyScroll(_bounds!);
    if (delta == Offset.zero) {
      _stopTimer();
      return;
    }
    onScroll?.call(delta);
  }

  bool _isNearEdge(Offset pos, Rect bounds) {
    if (autoScrollThreshold <= 0) return false;
    if (pos.dy - bounds.top < autoScrollThreshold) return true;
    if (bounds.bottom - pos.dy < autoScrollThreshold) return true;
    if (pos.dx - bounds.left < autoScrollThreshold) return true;
    if (bounds.right - pos.dx < autoScrollThreshold) return true;
    return false;
  }

  /// Computes and applies scroll.  Returns the actual delta applied.
  Offset _applyScroll(Rect viewportBounds) {
    if (autoScrollThreshold <= 0) return Offset.zero;

    final pos = _lastGlobalPosition;
    final threshold = autoScrollThreshold;
    final maxSpeed = autoScrollMaxSpeed;

    double vSpeed = 0, hSpeed = 0;

    if (verticalScrollController?.hasClients == true) {
      final topDist = pos.dy - viewportBounds.top;
      final bottomDist = viewportBounds.bottom - pos.dy;
      if (topDist < threshold) vSpeed = -_ramp(topDist, threshold, maxSpeed);
      else if (bottomDist < threshold) vSpeed = _ramp(bottomDist, threshold, maxSpeed);
    }
    if (horizontalScrollController?.hasClients == true) {
      final leftDist = pos.dx - viewportBounds.left;
      final rightDist = viewportBounds.right - pos.dx;
      if (leftDist < threshold) hSpeed = -_ramp(leftDist, threshold, maxSpeed);
      else if (rightDist < threshold) hSpeed = _ramp(rightDist, threshold, maxSpeed);
    }

    if (hSpeed.abs() < 0.01 && vSpeed.abs() < 0.01) return Offset.zero;

    double actualDx = 0, actualDy = 0;

    final vc = verticalScrollController;
    if (vc?.hasClients == true && vSpeed.abs() > 0.01) {
      final old = vc!.offset;
      final neo = (old + vSpeed).clamp(vc.position.minScrollExtent, vc.position.maxScrollExtent);
      final a = neo - old;
      if (a.abs() > 0.01) { vc.jumpTo(neo); actualDy = a; }
    }

    final hc = horizontalScrollController;
    if (hc?.hasClients == true && hSpeed.abs() > 0.01) {
      final old = hc!.offset;
      final neo = (old + hSpeed).clamp(hc.position.minScrollExtent, hc.position.maxScrollExtent);
      final a = neo - old;
      if (a.abs() > 0.01) { hc.jumpTo(neo); actualDx = a; }
    }

    return Offset(actualDx, actualDy);
  }

  void _stopTimer() { _timer?.cancel(); _timer = null; }
  void dispose() { _stopTimer(); }

  static double _ramp(double d, double t, double max) {
    if (d >= t) return 0;
    if (d <= 0) return max;
    return max * (1.0 - d / t);
  }
}
