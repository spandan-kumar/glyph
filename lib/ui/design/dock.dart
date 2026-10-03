import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

class DockItem {
  const DockItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Floating three-item navigation. The active item is marked by a small lit
/// LED dot, not a filled pill.
class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    this.accent = Lb.phosphor,
  });

  final List<DockItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Lb.panel.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(Lb.rPanel),
              border: Border.all(color: Lb.line),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _DockButton(
                      item: items[i],
                      active: i == index,
                      accent: accent,
                      onTap: () {
                        if (i != index) HapticFeedback.selectionClick();
                        onSelect(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.item, required this.active, required this.accent, required this.onTap});

  final DockItem item;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 84,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: active ? Lb.text : Lb.text3),
              const SizedBox(height: 3),
              Text(item.label,
                  style: LbType.label.copyWith(color: active ? Lb.text : Lb.text3, letterSpacing: 0.6)),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: Lb.fast,
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? accent : Colors.transparent,
                  boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: 0.8), blurRadius: 6)] : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
