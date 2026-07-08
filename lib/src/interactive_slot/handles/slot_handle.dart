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

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      if (_dragStarted) onEnd();
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
        onEnd();
      }
      _finish(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (_dragStarted) onEnd();
      _finish(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_pointer == pointer) {
      if (_dragStarted) onEnd();
      _finish(pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_dragStarted) onEnd();
    _pointer = null;
    _startGlobal = null;
    _dragStarted = false;
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
/// Uses a [StatefulWidget] so the [SlotDragRecognizer] is created once and
/// preserved across parent rebuilds — this keeps the drag gesture alive
/// during auto-scroll and notifier-triggered rebuilds.
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
        DragMode.extendStart => config.enableExtendStart,
        DragMode.extendEnd => config.enableExtendEnd,
      };

  @override
  State<SlotHandleZone> createState() => _SlotHandleZoneState();
}

class _SlotHandleZoneState extends State<SlotHandleZone> {
  SlotDragRecognizer? _recognizer;

  @override
  void initState() {
    super.initState();
    _createRecognizer();
  }

  @override
  void didUpdateWidget(covariant SlotHandleZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recreate the recognizer only when the config or callbacks change
    // in a way that affects its behaviour.  Simple reference checks.
    if (oldWidget.config.dragThreshold != widget.config.dragThreshold ||
        oldWidget.dragMode != widget.dragMode) {
      _recognizer?.dispose();
      _recognizer = null;
      _createRecognizer();
    }
  }

  void _createRecognizer() {
    _recognizer ??= SlotDragRecognizer(
      dragThreshold: widget.config.dragThreshold,
      preSetMode: widget.dragMode,
      onStart: (mode) => widget.onDragStart?.call(mode ?? widget.dragMode),
      onUpdate: (details) => widget.onDragUpdate?.call(details),
      onEnd: () => widget.onDragEnd?.call(),
      onTap: () => widget.onTap?.call(),
    );
  }

  @override
  void dispose() {
    if (_recognizer?.isActive == true) {
      final cb = _recognizer!.onEnd;
      WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    }
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._isEnabled) return widget.child ?? const SizedBox.shrink();

    // Update callback references on every build (they're closures that
    // can capture changing state).  The recognizer instance stays the same.
    final r = _recognizer!;
    r.onStart = (mode) => widget.onDragStart?.call(mode ?? widget.dragMode);
    r.onUpdate = (details) => widget.onDragUpdate?.call(details);
    r.onEnd = () => widget.onDragEnd?.call();
    r.onTap = () => widget.onTap?.call();
    r.dragThreshold = widget.config.dragThreshold;
    r.preSetMode = widget.dragMode;

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        SlotDragRecognizer: GestureRecognizerFactoryWithHandlers<
            SlotDragRecognizer>(
          () => _recognizer!,
          (_) {},
        ),
      },
      child: widget.child ?? const SizedBox.expand(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Handle indicator (small pill shape).
// ═══════════════════════════════════════════════════════════════════════════

/// A small rounded pill used as a visual indicator on resize handles.
class HandlePill extends StatelessWidget {
  const HandlePill({super.key, required this.color, this.width = 36, this.height = 4});

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
