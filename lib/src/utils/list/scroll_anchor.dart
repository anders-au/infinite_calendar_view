import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A rendered item's leading edge in viewport coordinates, including its header.
class ListScrollAnchor {
  const ListScrollAnchor(this.key, this.leading, this.scrollOffset);

  final Key key;
  final double leading;
  final double scrollOffset;
}

/// Identity makes a correction apply once, even across subsequent rebuilds.
class ListScrollCorrection {
  const ListScrollCorrection(this.delta);

  final double delta;
}

/// Tracks mounted items only; no global keys or off-screen measurements needed.
class ListAnchorRegistry {
  final _items = <Key, _RenderAnchoredItem>{};

  ListScrollAnchor? captureItem(Key key) {
    final item = _items[key];
    if (item == null || !item.attached || !item.hasSize) return null;
    final viewport = RenderAbstractViewport.of(item);
    if (viewport is! RenderBox) return null;
    final leading = item.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final position = Scrollable.of(item.context).position;
    return ListScrollAnchor(key, leading, position.pixels);
  }

  ListScrollAnchor? captureAnchor() {
    ListScrollAnchor? first;
    for (final entry in _items.entries) {
      final anchor = captureItem(entry.key);
      if (anchor == null || anchor.leading + entry.value.size.height <= 0) {
        continue;
      }
      if (first == null || anchor.leading < first.leading) first = anchor;
    }
    return first;
  }
}

class AnchoredListItem extends SingleChildRenderObjectWidget {
  const AnchoredListItem({
    super.key,
    required this.registry,
    required this.itemKey,
    required super.child,
  });

  final ListAnchorRegistry registry;
  final Key itemKey;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchoredItem(registry, itemKey, context);
}

class _RenderAnchoredItem extends RenderProxyBox {
  _RenderAnchoredItem(this.registry, this.itemKey, this.context);

  final ListAnchorRegistry registry;
  final Key itemKey;
  final BuildContext context;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    registry._items[itemKey] = this;
  }

  @override
  void detach() {
    if (identical(registry._items[itemKey], this)) {
      registry._items.remove(itemKey);
    }
    super.detach();
  }
}

/// Correct the viewport during layout, preserving the live scroll activity.
class ScrollCorrectionSliver extends SingleChildRenderObjectWidget {
  const ScrollCorrectionSliver({
    super.key,
    required this.correction,
    required Widget sliver,
  }) : super(child: sliver);

  final ListScrollCorrection? correction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScrollCorrectionSliver()..correction = correction;

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxySliver renderObject,
  ) {
    (renderObject as _RenderScrollCorrectionSliver).correction = correction;
  }
}

class _RenderScrollCorrectionSliver extends RenderProxySliver {
  ListScrollCorrection? _correction;
  bool _pending = false;

  set correction(ListScrollCorrection? value) {
    if (identical(value, _correction)) return;
    _correction = value;
    _pending = value != null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_pending) {
      _pending = false;
      final delta = _correction!.delta;
      if (delta != 0.0) {
        geometry = SliverGeometry(scrollOffsetCorrection: delta);
        return;
      }
    }
    super.performLayout();
  }
}
