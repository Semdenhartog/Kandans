import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

/// Gouden tegel naar de shop (in Ik). Altijd donker-goud, zoals Premium en Luxe.
class ShopTile extends StatelessWidget {
  const ShopTile({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD9BF92), goldLight = Color(0xFFF0DDB6), goldDeep = Color(0xFFB8955F);
    return Semantics(
      button: true,
      label: 'Shop: routeposters, Luxe-ontwerpen, Premium en schoenen',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            markShopSeen();
            context.push('/shop');
          },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2116), Color(0xFF14110C)],
              ),
              border: Border.all(color: goldDeep.withValues(alpha: 0.7)),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [goldLight, goldDeep]),
                ),
                child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF1A1510), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shop', style: TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 18, color: rwZandAvond.text)),
                  const SizedBox(height: 2),
                  Text('Routeposters, Luxe-ontwerpen en schoenen',
                      style: TextStyle(color: rwZandAvond.muted, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const Icon(Icons.chevron_right, color: gold),
            ]),
          ),
        ),
      ),
    );
  }
}

const _seenKey = 'shop_seen';

/// Shop geopend: het "nieuw"-stipje verdwijnt.
void markShopSeen() {
  SharedPreferences.getInstance().then((p) => p.setBool(_seenKey, true)).catchError((Object _) => false);
  shopSeen.value = true;
}

/// Of de shop al eens geopend is (voor het stipje op het tasje).
final shopSeen = ValueNotifier<bool>(true);

/// Eén keer inlezen bij het opstarten van een tasje.
bool _seenLoaded = false;
void _loadSeen() {
  if (_seenLoaded) return;
  _seenLoaded = true;
  SharedPreferences.getInstance().then((p) => shopSeen.value = p.getBool(_seenKey) ?? false).catchError((Object _) => true);
}

/// Klein goud tasje voor in een kopbalk, met een stipje zolang je de shop nog niet bekeek.
class ShopIconButton extends StatelessWidget {
  const ShopIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    _loadSeen();
    return ValueListenableBuilder<bool>(
      valueListenable: shopSeen,
      builder: (context, seen, _) => IconButton(
        tooltip: seen ? 'Shop' : 'Shop (nieuw)',
        icon: Badge(
          isLabelVisible: !seen,
          smallSize: 8,
          backgroundColor: const Color(0xFFD9BF92),
          child: Icon(Icons.shopping_bag_outlined, color: RwColors.accent),
        ),
        onPressed: () {
          markShopSeen();
          context.push('/shop');
        },
      ),
    );
  }
}
