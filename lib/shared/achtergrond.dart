import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Eigen achtergrondbeeld uit `assets/achtergronden/` (zie `tools/maak_achtergronden.py`), licht of donker naar de weergave.
/// Namen: glas_vlekken, aura, mist_heuvels, zonsopkomst. Met [vast] een effen kleur in plaats van het beeld.
BoxDecoration achtergrondBox(String naam, [Color? vast]) => vast != null
    ? BoxDecoration(color: vast)
    : BoxDecoration(
        color: RwColors.background,
        image: DecorationImage(
          image: AssetImage('assets/achtergronden/${naam}_${RwColors.isDark ? 'donker' : 'licht'}.jpg'),
          fit: BoxFit.cover,
        ),
      );
