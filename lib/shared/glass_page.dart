import 'package:flutter/material.dart';

import 'aura.dart';

/// Elke pagina van de app ligt op dezelfde zachte glasachtergrond (de aura). De schermen zelf zijn doorzichtig
/// (`scaffoldBackgroundColor`), de kaarten en balken erop zijn matglas. Zo krijgt de hele app één look,
/// ook schermen die verder nooit aangepast zijn.
class GlassPageTransitions extends PageTransitionsBuilder {
  const GlassPageTransitions();

  static const _fade = FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _fade.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      Stack(fit: StackFit.expand, children: [const RwAura(), child]),
    );
  }
}
