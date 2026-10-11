import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The Lightbox page transition: a fade with a 3% rise, never Material's
/// slide. Every pushed screen uses it.
Route<T> lbRoute<T>(WidgetBuilder builder, {RouteSettings? settings, bool fullscreenDialog = false}) =>
    PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: Lb.medium,
      reverseTransitionDuration: Lb.fast,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Lb.ease);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
