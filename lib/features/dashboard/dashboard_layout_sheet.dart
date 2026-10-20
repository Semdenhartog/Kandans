import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'dashboard_providers.dart';

/// Kaarten op Vandaag ordenen (slepen) en aan- of uitzetten.
void showDashLayoutSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _DashLayoutSheet(),
  );
}

class _DashLayoutSheet extends ConsumerWidget {
  const _DashLayoutSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dashLayoutProvider);
    final n = ref.read(dashLayoutProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Indeling van Vandaag',
                        style: TextStyle(fontFamily: RwFonts.display, fontFeatures: rwTnum, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  TextButton(onPressed: n.reset, child: const Text('Standaard')),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Het oordeel en de beste vertrektijd staan altijd bovenaan. Sleep de rest in de volgorde die jij wilt, of zet kaarten uit.',
                style: TextStyle(color: RwColors.muted, height: 1.4),
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: layout.order.length,
                onReorder: n.move,
                itemBuilder: (context, i) {
                  final c = layout.order[i];
                  final on = !layout.hidden.contains(c);
                  return ListTile(
                    key: ValueKey(c),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Semantics(
                        label: '${c.label} verslepen',
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_indicator, color: RwColors.subtle),
                        ),
                      ),
                    ),
                    title: Text(c.label, style: TextStyle(color: on ? RwColors.text : RwColors.subtle)),
                    subtitle: Text(c.description, style: const TextStyle(color: RwColors.subtle, fontSize: 12)),
                    trailing: Switch(value: on, onChanged: (_) => n.toggle(c)),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
