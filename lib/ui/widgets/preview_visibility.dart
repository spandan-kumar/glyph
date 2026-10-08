import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cached sliver children and nested grids can exist outside the viewport.
bool previewIsVisible(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return false;
  final bounds = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  final screen = MediaQuery.maybeSizeOf(context);
  if (screen != null && !bounds.overlaps(Offset.zero & screen)) return false;
  for (
    var ancestor = box.parent;
    ancestor != null;
    ancestor = ancestor.parent
  ) {
    if (ancestor is RenderBox &&
        ancestor is RenderAbstractViewport &&
        ancestor.hasSize) {
      final clip = MatrixUtils.transformRect(
        ancestor.getTransformTo(null),
        Offset.zero & ancestor.size,
      );
      if (!bounds.overlaps(clip)) return false;
    }
  }
  return true;
}
