import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../domain/record_layout.dart';
import '../../shared/widgets.dart';

/// Opnamescherm indelen: kies welke cijfers je tijdens het lopen ziet.
/// Geeft bij teruggaan de (aangepaste) indelingen en de gekozen indeling terug.
class RecordLayoutScreen extends StatefulWidget {
  const RecordLayoutScreen({super.key, required this.layouts, required this.selected});
  final List<RecordLayout> layouts;
  final int selected;

  @override
  State<RecordLayoutScreen> createState() => _RecordLayoutScreenState();
}

class _RecordLayoutScreenState extends State<RecordLayoutScreen> {
  late List<RecordLayout> _layouts = List.of(widget.layouts);
  late int _selected = widget.selected.clamp(0, widget.layouts.length - 1);

  void _done() => Navigator.of(context).pop((layouts: _layouts, selected: _selected));

  Future<void> _edit(int? index) async {
    final start = index == null ? RecordLayout(name: tr('Mijn indeling')) : _layouts[index];
    final res = await Navigator.of(context).push<RecordLayout>(
      MaterialPageRoute(builder: (_) => _LayoutEditor(layout: start)),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (index == null) {
        _layouts.add(res);
        _selected = _layouts.length - 1;
      } else {
        _layouts[index] = res;
      }
    });
  }

  Future<void> _remove(int i) async {
    if (_layouts.length <= 1) return;
    final ok = await confirmDialog(context,
        title: tr('Indeling verwijderen?'), message: trf('"{naam}" verdwijnt.', {'naam': _layouts[i].name}));
    if (!ok || !mounted) return;
    setState(() {
      _layouts.removeAt(i);
      if (_selected >= _layouts.length) _selected = _layouts.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Opnamescherm indelen')),
          actions: [TextButton(onPressed: _done, child: Text(tr('Klaar')))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr('Kies wat je tijdens het lopen ziet. Tijdens je run tik je op de naam boven de cijfers om te wisselen.'),
              style: TextStyle(color: RwColors.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final (i, l) in _layouts.indexed)
              Card(
                child: ListTile(
                  leading: Icon(i == _selected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: i == _selected ? RwColors.accent : RwColors.subtle),
                  title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [tr(l.main.label), ...l.fields.map((f) => tr(f.label))].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: i == _selected,
                  onTap: () => setState(() => _selected = i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: tr('Aanpassen'), icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(i)),
                    if (_layouts.length > 1)
                      IconButton(tooltip: tr('Verwijderen'), icon: const Icon(Icons.delete_outline), onPressed: () => _remove(i)),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: Text(tr('Nieuwe indeling'))),
            TextButton(
              onPressed: () => setState(() {
                _layouts = List.of(RecordLayout.presets);
                _selected = 0;
              }),
              child: Text(tr('Terug naar de standaardindelingen')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutEditor extends StatefulWidget {
  const _LayoutEditor({required this.layout});
  final RecordLayout layout;

  @override
  State<_LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<_LayoutEditor> {
  late final _name = TextEditingController(text: widget.layout.name);
  late RecordLayout _l = widget.layout;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle(RecField f) {
    final list = List.of(_l.fields);
    if (list.contains(f)) {
      list.remove(f);
    } else if (list.length < RecordLayout.maxFields) {
      list.add(f);
    }
    setState(() => _l = _l.copyWith(fields: list));
  }

  void _save() {
    final name = _name.text.trim().isEmpty ? tr('Mijn indeling') : _name.text.trim();
    Navigator.of(context).pop(_l.copyWith(name: name));
  }

  @override
  Widget build(BuildContext context) {
    final big = _l.style == RecStyle.big;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Indeling aanpassen')),
        actions: [TextButton(onPressed: _save, child: Text(tr('Bewaren')))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: tr('Naam'))),
          const SizedBox(height: 18),
          Text(tr('Weergave'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<RecStyle>(
            segments: [
              ButtonSegment(value: RecStyle.ring, label: Text(tr('Ring met cijfers'))),
              ButtonSegment(value: RecStyle.big, label: Text(tr('Twee grote cijfers'))),
            ],
            selected: {_l.style},
            onSelectionChanged: (v) => setState(() => _l = _l.copyWith(style: v.first)),
          ),
          const SizedBox(height: 18),
          Text(tr('Hoofdcijfer'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in RecField.values)
              ChoiceChip(label: Text(tr(f.label)), selected: _l.main == f, onSelected: (_) => setState(() => _l = _l.copyWith(main: f))),
          ]),
          const SizedBox(height: 18),
          Text(big ? tr('Tweede groot cijfer') : trf('Kleine cijfers (max. {n}, in deze volgorde)', {'n': RecordLayout.maxFields}),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (big)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in RecField.values)
                if (f != _l.main)
                  ChoiceChip(
                    label: Text(tr(f.label)),
                    selected: _l.fields.isNotEmpty && _l.fields.first == f,
                    onSelected: (_) => setState(() => _l = _l.copyWith(fields: [f])),
                  ),
            ])
          else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in RecField.values)
                FilterChip(
                  label: Text(_l.fields.contains(f) ? '${_l.fields.indexOf(f) + 1}. ${tr(f.label)}' : tr(f.label)),
                  selected: _l.fields.contains(f),
                  onSelected: (_) => _toggle(f),
                ),
            ]),
            const SizedBox(height: 18),
            Text(tr('Kolommen'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
              selected: {_l.columns},
              onSelectionChanged: (v) => setState(() => _l = _l.copyWith(columns: v.first)),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            tr('Cadans heeft een loopsensor nodig (Profiel → Hartslagband en loopsensor). Hoogtemeters zijn het nauwkeurigst met een barometer in je telefoon.'),
            style: TextStyle(color: RwColors.subtle, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
