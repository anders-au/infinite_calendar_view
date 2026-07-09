import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../slot_config.dart';
import '../slot_selection.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Immediate-drag gesture recognizer.
//
// Unlike LongPressGestureRecognizer (which has a built-in delay) or
// PanGestureRecognizer (which loses to scroll in a gesture arena), this
// recognizer enters the arena on pointer-down and resolves to *accepted*
// as soon as the pointer moves past the configured drag threshold.  This
// gives zero-delay drags that always win over the planner's scroll
// recognizers while still allowing taps (pointer-up before threshold).
// ═══════════════════════════════════════════════════════════════════════════

class SlotDragRecognizer extends OneSequenceGestureRecognizer {
  SlotDragRecognizer({
    required this.dragThreshold,
    this.preSetMode,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onTap,
  });

  double dragThreshold;

  /// If non-null, the drag mode is pre-determined (e.g. multi-day handle
  /// zones).  If null, the caller determines the mode from the pointer
  /// position on the first update.
  DragMode? preSetMode;

  void Function(DragMode? mode) onStart;
  void Function(DragUpdateDetails) onUpdate;
  VoidCallback onEnd;
  VoidCallback onTap;

  Offset? _startGlobal;
  bool _dragStarted = false;
  int? _pointer;

  /// Whether this recognizer is actively tracking a drag (pointer down
  /// and moved past the threshold).  Used by the handle zone to decide
  /// whether to fire [onEnd] during disposal.
  bool get isActive => _pointer != null && _dragStarted;

  void cancelActiveDrag() {
    _completeDrag();
    final pointer = _pointer;
    if (pointer != null) {
      _finish(pointer);
    }
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      _completeDrag();
      stopTrackingPointer(_pointer!);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
    startTrackingPointer(event.pointer);
    _pointer = event.pointer;
    _startGlobal = event.position;
    _dragStarted = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      if (_startGlobal == null) return;
      final delta = event.position - _startGlobal!;
      if (!_dragStarted) {
        if (delta.distance < dragThreshold) return;
        _dragStarted = true;
        resolve(GestureDisposition.accepted);
        onStart(preSetMode);
      }
      onUpdate(
        DragUpdateDetails(
          sourceTimeStamp: event.timeStamp,
          delta: event.localDelta,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    } else if (event is PointerUpEvent) {
      if (!_dragStarted) {
        onTap();
        resolve(GestureDisposition.accepted);
      } else {
        _completeDrag();
      }
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      _completeDrag();
      _finish(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_pointer == pointer) {
      _completeDrag();
      _finish(pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _completeDrag();
    _pointer = null;
    _startGlobal = null;
    _dragStarted = false;
  }

  void _completeDrag() {
    if (!_dragStarted) return;
    _dragStarted = false;
    onEnd();
  }

  void _finish(int pointer) {
    if (_pointer == pointer) {
      stopTrackingPointer(pointer);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
  }

  @override
  String get debugDescription => 'SlotDragRecognizer';
}

// ═══════════════════════════════════════════════════════════════════════════
// Long-press-then-drag gesture recognizer.
//
// Used for the shift (body) zone so that quick flings / swipes over a
// slot pass through to the calendar's scroll views.  The recognizer
// enters the arena on pointer-down and:
//   1. If the pointer moves past the configured wiggle-room BEFORE the
//      long-press duration elapses → reject (scroll wins).
//   2. If the pointer stays within wiggle-room for the duration →
//      accept and begin tracking drag moves.
//   3. If the pointer goes up before the duration → fire onTap.
//
// This is distinct from [SlotDragRecognizer] (used for resize handles)
// which accepts immediately on any movement past the drag threshold.
// ═══════════════════════════════════════════════════════════════════════════

class LongPressDragRecognizer extends OneSequenceGestureRecognizer {
  LongPressDragRecognizer({
    required this.longPressDuration,
    required this.dragThreshold,
    this.preSetMode,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onTap,
  });

  /// How long the user must hold before the drag commits.
  Duration longPressDuration;

  /// Maximum pointer movement allowed during the hold phase.
  /// Exceeding this before [longPressDuration] elapses causes rejection.
  double dragThreshold;

  /// If non-null, the drag mode is pre-determined.
  DragMode? preSetMode;

  void Function(DragMode? mode) onStart;
  void Function(DragUpdateDetails) onUpdate;
  VoidCallback onEnd;
  VoidCallback onTap;

  Offset? _startGlobal;
  bool _dragStarted = false;
  int? _pointer;
  Timer? _deadlineTimer;

  /// Whether this recognizer is actively tracking a drag.
  bool get isActive => _pointer != null && _dragStarted;

  void cancelActiveDrag() {
    _cancelDeadline();
    _completeDrag();
    final pointer = _pointer;
    if (pointer != null) {
      _finish(pointer);
    }
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      _completeDrag();
      _cancelDeadline();
      stopTrackingPointer(_pointer!);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
    startTrackingPointer(event.pointer);
    _pointer = event.pointer;
    _startGlobal = event.position;
    _dragStarted = false;
    _deadlineTimer = Timer(longPressDuration, _onDeadlineReached);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      if (_startGlobal == null) return;
      if (!_dragStarted) {
        // Still in the hold phase — check if the user moved too far.
        final delta = event.position - _startGlobal!;
        if (delta.distance > dragThreshold) {
          // User swiped before the long-press duration → reject so
          // the scroll view can take over.
          _cancelDeadline();
          resolve(GestureDisposition.rejected);
          _finish(event.pointer);
          return;
        }
        // Within wiggle-room — keep waiting for the timer.
        return;
      }
      // Drag is active — forward the update.
      onUpdate(
        DragUpdateDetails(
          sourceTimeStamp: event.timeStamp,
          delta: event.localDelta,
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    } else if (event is PointerUpEvent) {
      if (!_dragStarted) {
        // Went up before the long-press duration → tap.
        _cancelDeadline();
        onTap();
        resolve(GestureDisposition.accepted);
      } else {
        _completeDrag();
      }
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      _cancelDeadline();
      _completeDrag();
      _finish(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_pointer == pointer) {
      _cancelDeadline();
      _completeDrag();
      _finish(pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _cancelDeadline();
    _completeDrag();
    _pointer = null;
    _startGlobal = null;
    _dragStarted = false;
  }

  /// Called by the long-press timer when the deadline is reached.
  /// If the pointer is still down, accept the gesture and begin
  /// tracking drags.
  void _onDeadlineReached() {
    if (_pointer == null) return;
    if (_dragStarted) return; // Already started (defensive).
    _dragStarted = true;
    resolve(GestureDisposition.accepted);
    onStart(preSetMode);
  }

  void _cancelDeadline() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }

  void _completeDrag() {
    if (!_dragStarted) return;
    _dragStarted = false;
    onEnd();
  }

  void _finish(int pointer) {
    if (_pointer == pointer) {
      stopTrackingPointer(pointer);
      _pointer = null;
      _startGlobal = null;
      _dragStarted = false;
    }
  }

  @override
  void dispose() {
    _cancelDeadline();
    super.dispose();
  }

  @override
  String get debugDescription => 'LongPressDragRecognizer';
}

// ═══════════════════════════════════════════════════════════════════════════
// SlotHandleZone — a narrow drag zone for one handle or the slot body.
// ═══════════════════════════════════════════════════════════════════════════

/// A positioned zone that captures drag gestures for a specific drag mode.
///
/// Three instances per slot:
/// * Start handle (top) → [DragMode.extendStart]
/// * End handle (bottom) → [DragMode.extendEnd]
/// * Body (middle) → [DragMode.shift]
///
/// Each can be independently enabled via [SlotInteractionConfig].
///
/// Uses a [StatefulWidget] so the gesture recognizer is created once and
/// preserved across parent rebuilds — this keeps the drag gesture alive
/// during auto-scroll and notifier-triggered rebuilds.
///
/// When [DragMode.shift], a [LongPressDragRecognizer] is used so quick
/// flings pass through to the calendar's scroll views.  Resize handles
/// ([extendStart], [extendEnd]) use the immediate [SlotDragRecognizer].
class SlotHandleZone extends StatefulWidget {
  const SlotHandleZone({
    super.key,
    required this.dragMode,
    required this.config,
    this.child,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
  });

  final DragMode dragMode;
  final SlotInteractionConfig config;
  final Widget? child;
  final void Function(DragMode mode)? onDragStart;
  final void Function(DragUpdateDetails details)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final VoidCallback? onTap;

  bool get _isEnabled => switch (dragMode) {
    DragMode.shift => config.enableShift,
    DragMode.extendStart => config.enableResize && config.enableResizeStart,
    DragMode.extendEnd => config.enableResize && config.enableResizeEnd,
  };

  @override
  State<SlotHandleZone> createState() => _SlotHandleZoneState();
}

class _SlotHandleZoneState extends State<SlotHandleZone> {
  OneSequenceGestureRecognizer? _recognizer;

  bool get _isShift => widget.dragMode == DragMode.shift;

  @override
  void initState() {
    super.initState();
    _createRecognizer();
  }

  @override
  void didUpdateWidget(covariant SlotHandleZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recreate the recognizer only when behaviour-affecting config
    // values or the drag mode change.
    final needsRebuild =
        oldWidget.config.dragThreshold != widget.config.dragThreshold ||
        oldWidget.config.longPressDuration != widget.config.longPressDuration ||
        oldWidget.dragMode != widget.dragMode;
    if (needsRebuild) {
      _recognizer?.dispose();
      _recognizer = null;
      _createRecognizer();
    }
  }

  void _createRecognizer() {
    if (_isShift) {
      _recognizer ??= LongPressDragRecognizer(
        longPressDuration: widget.config.longPressDuration,
        dragThreshold: widget.config.dragThreshold,
        preSetMode: widget.dragMode,
        onStart: (mode) => widget.onDragStart?.call(mode ?? widget.dragMode),
        onUpdate: (details) => widget.onDragUpdate?.call(details),
        onEnd: () => widget.onDragEnd?.call(),
        onTap: () => widget.onTap?.call(),
      );
    } else {
      _recognizer ??= SlotDragRecognizer(
        dragThreshold: widget.config.dragThreshold,
        preSetMode: widget.dragMode,
        onStart: (mode) => widget.onDragStart?.call(mode ?? widget.dragMode),
        onUpdate: (details) => widget.onDragUpdate?.call(details),
        onEnd: () => widget.onDragEnd?.call(),
        onTap: () => widget.onTap?.call(),
      );
    }
  }

  @override
  void dispose() {
    final r = _recognizer;
    if (r is SlotDragRecognizer && r.isActive) {
      r.cancelActiveDrag();
    } else if (r is LongPressDragRecognizer && r.isActive) {
      r.cancelActiveDrag();
    }
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._isEnabled) return widget.child ?? const SizedBox.shrink();

    final r = _recognizer!;

    // Update callback references on every build (they're closures that
    // can capture changing state).  The recognizer instance stays the same.
    if (r is SlotDragRecognizer) {
      r.onStart = (mode) => widget.onDragStart?.call(mode ?? widget.dragMode);
      r.onUpdate = (details) => widget.onDragUpdate?.call(details);
      r.onEnd = () => widget.onDragEnd?.call();
      r.onTap = () => widget.onTap?.call();
      r.dragThreshold = widget.config.dragThreshold;
      r.preSetMode = widget.dragMode;

      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          SlotDragRecognizer:
              GestureRecognizerFactoryWithHandlers<SlotDragRecognizer>(
                () => r,
                (_) {},
              ),
        },
        child: widget.child ?? const SizedBox.expand(),
      );
    } else if (r is LongPressDragRecognizer) {
      r.onStart = (mode) => widget.onDragStart?.call(mode ?? widget.dragMode);
      r.onUpdate = (details) => widget.onDragUpdate?.call(details);
      r.onEnd = () => widget.onDragEnd?.call();
      r.onTap = () => widget.onTap?.call();
      r.longPressDuration = widget.config.longPressDuration;
      r.dragThreshold = widget.config.dragThreshold;
      r.preSetMode = widget.dragMode;

      return RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: <Type, GestureRecognizerFactory>{
          LongPressDragRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressDragRecognizer>(
                () => r,
                (_) {},
              ),
        },
        child: widget.child ?? const SizedBox.expand(),
      );
    }

    return widget.child ?? const SizedBox.shrink();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Handle indicator (small pill shape).
// ═══════════════════════════════════════════════════════════════════════════

/// A small rounded pill used as a visual indicator on resize handles.
class HandlePill extends StatelessWidget {
  const HandlePill({
    super.key,
    required this.color,
    this.width = 36,
    this.height = 4,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
