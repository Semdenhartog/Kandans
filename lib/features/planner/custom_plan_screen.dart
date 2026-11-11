import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/custom_plan.dart';
import '../../domain/training_load.dart';
import '../../domain/training_plan.dart';
import '../../domain/weekly_load.dart';
import '../../shared/widgets.dart';
import 'custom_plan_pdf.dart';

/// Schema op maat: vragen naar je wensen, dan een uitgebreid schema in donker-goud, als PDF te downloaden.
void openCustomPlan(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomPlanScreen()));
}

const _wishesKey = 'custom_plan_wishes';

// Altijd donker-goud (luxe), ook als de app op licht staat.
const _bg = Color(0xFF13110E);
const _surface = Color(0xFF1C1814);
const _surfaceHigh = Color(0xFF25201B);
const _line = Color(0xFF352E26);
const _gold = Color(0xFFD9BF92);
const _goldDeep = Color(0xFFB8955F);
const _text = Color(0xFFF1E9DC);
const _muted = Color(0xFFBDB1A0);
const _subtle = Color(0xFF94897A);
const _onGold = Color(0xFF1A1510);

const _dayShort = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
const _dayLong = ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
const _months = ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'];

String _date(DateTime d) => '${_dayShort[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
String _hours(int minutes) => minutes >= 60 ? '${minutes ~/ 60}u${(minutes % 60).toString().padLeft(2, '0')}' : '$minutes min';

Color kindColor(SessionKind k) => switch (k) {
      SessionKind.easy => const Color(0xFF8CC99A),
      SessionKind.long => const Color(0xFF8FB3D9),
      SessionKind.tempo => const Color(0xFFE6C16A),
      SessionKind.interval => _gold,
      SessionKind.race => const Color(0xFFEF7F78),
    };

Color phaseColor(PlanPhase p) => switch (p) {
      PlanPhase.start || PlanPhase.basis => const Color(0xFF6E7F63),
      PlanPhase.opbouw => const Color(0xFF8C7652),
      PlanPhase.piek => _gold,
      PlanPhase.afbouw => const Color(0xFF8FB3D9),
      PlanPhase.herstel => const Color(0xFF8CC99A),
      PlanPhase.vrij => _line,
    };

class CustomPlanScreen extends ConsumerStatefulWidget {
  const CustomPlanScreen({super.key, this.debugWishes});

  /// Voor schermtests: meteen het schema voor deze wensen tonen.
  final PlanWishes? debugWishes;

  @override
  ConsumerState<CustomPlanScreen> createState() => _CustomPlanScreenState();
}

class _CustomPlanScreenState extends ConsumerState<CustomPlanScreen> {
  PlanWishes _w = const PlanWishes();
  int _step = 0;
  CustomPlan? _plan;
  double? _threshold;
  bool _loaded = false;
  bool _saving = false;
  bool _pdfBusy = false;
  final _goalTime = TextEditingController();
  final _fiveK = TextEditingController();

  static const _steps = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _goalTime.dispose();
    _fiveK.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final debug = widget.debugWishes;
    if (debug != null) {
      setState(() {
        _w = debug;
        _threshold = 300;
        _plan = buildCustomPlan(debug, start: DateTime.now().add(const Duration(days: 1)), thresholdPace: 300);
        _loaded = true;
      });
      return;
    }
    final p = await SharedPreferences.getInstance();
    final saved = PlanWishes.fromJson(jsonDecode(p.getString(_wishesKey) ?? 'null'));
    final runs = ref.read(activitiesProvider).value ?? await ref.read(activitiesProvider.future).catchError((_) => <Activity>[]);
    final now = DateTime.now();
    final weeks = weeklyTotals(runs, now, weeks: 4);
    final weekly = weeks.isEmpty ? 0.0 : weeks.fold<double>(0, (s, w) => s + w.km) / weeks.length;
    final recent = runs.where((r) => now.difference(r.startedAt).inDays <= 42);
    final longest = recent.fold<double>(0, (m, r) => r.distanceMeters / 1000 > m ? r.distanceMeters / 1000 : m);
    if (!mounted) return;
    setState(() {
      _threshold = runs.length >= 3 ? estimateThresholdPace(runs) : null;
      _w = saved ??
          PlanWishes(
            weeklyKm: weekly > 0 ? (weekly * 2).round() / 2 : 10,
            longestKm: longest > 0 ? (longest * 2).round() / 2 : 5,
          );
      if (_w.goalTimeSeconds != null) _goalTime.text = Fmt.duration(_w.goalTimeSeconds!);
      if (_w.recent5kSeconds != null) _fiveK.text = Fmt.duration(_w.recent5kSeconds!);
      _loaded = true;
    });
  }

  void _set(PlanWishes w) => setState(() => _w = w);

  Future<void> _make() async {
    final goal = Fmt.parseDuration(_goalTime.text);
    final five = Fmt.parseDuration(_fiveK.text);
    var w = _w.copyWith(
      goalTimeSeconds: goal,
      clearGoalTime: goal == null,
      recent5kSeconds: five,
      clear5k: five == null,
    );
    if (w.goal.isRace && w.raceDate == null) {
      w = w.copyWith(raceDate: DateTime.now().add(Duration(days: w.goal.defaultWeeks * 7)));
    }
    if (!w.goal.isRace) w = w.copyWith(clearRace: true);
    final plan = buildCustomPlan(w, start: DateTime.now().add(const Duration(days: 1)), thresholdPace: _threshold);
    final p = await SharedPreferences.getInstance();
    await p.setString(_wishesKey, jsonEncode(w.toJson()));
    setState(() {
      _w = w;
      _plan = plan;
    });
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).savePlan(plan.runSessions);
      ref.invalidate(planProvider);
      if (mounted) showMessage(context, tr('Je schema staat in je plan. Je training van vandaag zie je ook op Vandaag.'));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pdf() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _pdfBusy = true);
    try {
      await shareCustomPlanPdf(plan);
    } catch (_) {
      if (mounted) showMessage(context, tr('De PDF maken is niet gelukt. Probeer het opnieuw.'), error: true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: _gold, onPrimary: _onGold, surface: _surface, onSurface: _text),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: _text, displayColor: _text),
        iconTheme: const IconThemeData(color: _gold),
        dividerColor: _line,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _text,
          elevation: 0,
          title: Text(tr('Schema op maat'), style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, color: _text)),
          actions: [
            if (plan != null)
              IconButton(
                tooltip: tr('Wensen aanpassen'),
                icon: const Icon(Icons.tune, color: _gold),
                onPressed: () => setState(() {
                  _plan = null;
                  _step = 0;
                }),
              ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : plan == null
                ? _wizard()
                : _PlanResult(plan: plan, saving: _saving, pdfBusy: _pdfBusy, onSave: _save, onPdf: _pdf),
      ),
    );
  }

  // ---------------------------------------------------------------- vragen

  Widget _wizard() {
    final pages = [_goalPage, _whenPage, _timePage, _levelPage, _daysPage, _extraPage];
    final last = _step == _steps - 1;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Row(children: [
          for (var i = 0; i < _steps; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: i <= _step ? _gold : _line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ]),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(_step), child: pages[_step]()),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            if (_step > 0)
              TextButton(
                onPressed: () => setState(() => _step--),
                child: Text(tr('Terug'), style: const TextStyle(color: _muted)),
              ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: _onGold, minimumSize: const Size(160, 52)),
              onPressed: last ? _make : () => setState(() => _step++),
              icon: Icon(last ? Icons.auto_awesome : Icons.arrow_forward, size: 18),
              label: Text(last ? tr('Maak mijn schema') : tr('Verder')),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _page(String nr, String title, String sub, List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text('$nr  ${tr('VAN')} 06', style: const TextStyle(fontFamily: 'KadansMono', fontSize: 12, letterSpacing: 1.6, color: _subtle)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 30, height: 1.05, color: _gold)),
          const SizedBox(height: 8),
          Text(sub, style: const TextStyle(fontSize: 15, height: 1.45, color: _muted)),
          const SizedBox(height: 22),
          ...children,
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: _subtle)),
      );

  Widget _choice({required bool selected, required String title, String? subtitle, IconData? icon, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? _surfaceHigh : _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RwRadius.m),
            side: BorderSide(color: selected ? _gold : _line, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(RwRadius.m),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                if (icon != null) ...[Icon(icon, color: selected ? _gold : _subtle), const SizedBox(width: 14)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: selected ? _gold : _text)),
                    if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 13, color: _muted))],
                  ]),
                ),
                if (selected) const Icon(Icons.check_circle, color: _gold, size: 20),
              ]),
            ),
          ),
        ),
      );

  Widget _chips<T>(List<T> values, T? selected, String Function(T) label, void Function(T) pick, {bool Function(T)? isOn}) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(label(v)),
              selected: isOn?.call(v) ?? v == selected,
              onSelected: (_) => pick(v),
              showCheckmark: false,
              backgroundColor: _surface,
              selectedColor: _gold,
              side: BorderSide(color: (isOn?.call(v) ?? v == selected) ? _gold : _line),
              labelStyle: TextStyle(color: (isOn?.call(v) ?? v == selected) ? _onGold : _text, fontWeight: FontWeight.w600),
            ),
        ],
      );

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        activeThumbColor: _onGold,
        activeTrackColor: _gold,
        title: Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: const TextStyle(color: _muted, fontSize: 13)),
      );

  Widget _slider(String label, double value, double min, double max, int divisions, String Function(double) shown, ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: _text, fontWeight: FontWeight.w600))),
          Text(shown(value), style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 20, color: _gold, fontFeatures: rwTnum)),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: _gold,
          inactiveColor: _line,
          onChanged: onChanged,
        ),
      ]);

  Widget _goalPage() => _page('01', tr('Waar train je voor?'), tr('Kies je doel. Het schema past zich hierop aan: opbouw, trainingen en tempo\'s.'), [
        for (final g in PlanGoal.values)
          _choice(
            selected: _w.goal == g,
            title: tr(g.label),
            subtitle: tr(g.subtitle),
            icon: switch (g) {
              PlanGoal.beginnen => Icons.directions_walk,
              PlanGoal.terugkomen => Icons.healing_outlined,
              PlanGoal.fit => Icons.favorite_border,
              PlanGoal.sneller => Icons.bolt_outlined,
              _ => Icons.flag_outlined,
            },
            onTap: () => _set(_w.copyWith(goal: g, weeks: g.defaultWeeks, clearRace: true)),
          ),
      ]);

  Widget _whenPage() {
    final g = _w.goal;
    if (!g.isRace) {
      final (lo, hi) = g.isStarter ? (g == PlanGoal.beginnen ? (6, 16) : (4, 12)) : (6, 24);
      return _page('02', tr('Hoe lang?'), tr('Zonder wedstrijd kies je zelf hoe lang het schema duurt.'), [
        _slider(tr('Aantal weken'), _w.weeks.toDouble(), lo.toDouble(), hi.toDouble(), hi - lo, (v) => '${v.round()}', (v) => _set(_w.copyWith(weeks: v.round()))),
        Text(trf('Advies: {n} weken.', {'n': '${g.defaultWeeks}'}), style: const TextStyle(color: _subtle, fontSize: 13)),
      ]);
    }
    final races = (ref.watch(racesProvider).value ?? const <RaceEvent>[]).where((r) => r.daysUntil >= 7).toList();
    final date = _w.raceDate ?? DateTime.now().add(Duration(days: g.defaultWeeks * 7));
    final weeks = (date.difference(DateTime.now()).inDays / 7).ceil();
    return _page('02', tr('Wanneer is je wedstrijd?'), tr('Kies een wedstrijd uit Mijn wedstrijden of een datum.'), [
      for (final r in races)
        _choice(
          selected: _w.raceName == r.name && _w.raceDate != null && _w.raceDate!.difference(r.raceDate).inDays == 0,
          title: r.name,
          subtitle: '${_date(r.raceDate)} · ${(r.distanceMeters / 1000).toStringAsFixed(r.distanceMeters % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km',
          icon: Icons.emoji_events_outlined,
          onTap: () {
            final match = PlanGoal.values.where((x) => x.meters != null && (x.meters! - r.distanceMeters).abs() < 800).firstOrNull;
            if (r.goalTimeSeconds > 0) _goalTime.text = Fmt.duration(r.goalTimeSeconds);
            _set(_w.copyWith(goal: match ?? _w.goal, raceDate: r.raceDate, raceName: r.name));
          },
        ),
      _choice(
        selected: _w.raceName == null,
        title: trf('Datum: {datum}', {'datum': _date(date)}),
        subtitle: trf('Over {n} weken · tik om te wijzigen', {'n': '$weeks'}),
        icon: Icons.event_outlined,
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime.now().add(const Duration(days: 7)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) _set(PlanWishes.fromJson({..._w.toJson(), 'race': picked.toIso8601String()}..remove('raceName'))!);
        },
      ),
      if (weeks < g.minWeeks)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(trf('Let op: {n} weken is kort voor een {doel}. Het schema bouwt voorzichtig op.', {'n': '$weeks', 'doel': tr(g.label)}),
              style: const TextStyle(color: Color(0xFFE6C16A), fontSize: 13)),
        ),
    ]);
  }

  Widget _timePage() {
    final g = _w.goal;
    final field = (TextEditingController c, String label, String hint) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: c,
            keyboardType: TextInputType.datetime,
            style: const TextStyle(color: _text, fontFamily: RwFonts.display, fontWeight: FontWeight.w700, fontSize: 20, fontFeatures: rwTnum),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              labelStyle: const TextStyle(color: _muted),
              hintStyle: const TextStyle(color: _subtle),
              filled: true,
              fillColor: _surface,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(RwRadius.m), borderSide: const BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(RwRadius.m), borderSide: const BorderSide(color: _gold, width: 1.6)),
            ),
          ),
        );
    return _page('03', tr('Tijden'), tr('Allebei optioneel. Met een recente 5 km-tijd kloppen je tempo\'s beter.'), [
      if (g.isRace) field(_goalTime, trf('Doeltijd {doel}', {'doel': tr(g.label)}), g.meters! >= 21000 ? '1:55:00' : '50:00'),
      if (!g.isStarter) field(_fiveK, tr('Recente 5 km-tijd'), '27:30'),
      _info(_threshold == null
          ? tr('Je hebt nog weinig runs in de app. Zonder 5 km-tijd zijn de tempo\'s een schatting; loop dan vooral op gevoel.')
          : trf('Uit je runs schatten we je drempeltempo op {tempo} /km.', {'tempo': fmtPace(_threshold!)})),
      if (g.isStarter) _info(tr('Bij beginnen en terugkomen loop je op gevoel, tijden zijn niet nodig.')),
    ]);
  }

  Widget _info(String t) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(RwRadius.m), border: Border.all(color: _line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: _gold, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: const TextStyle(color: _muted, fontSize: 13, height: 1.45))),
        ]),
      );

  Widget _levelPage() => _page('04', tr('Je niveau'), tr('Ingevuld vanuit je logboek. Pas het gerust aan.'), [
        _slider(tr('Kilometers per week nu'), _w.weeklyKm, 0, 100, 200, (v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',')} km',
            (v) => _set(_w.copyWith(weeklyKm: (v * 2).round() / 2))),
        _slider(tr('Langste run (laatste 6 weken)'), _w.longestKm, 0, 40, 80, (v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1).replaceAll('.', ',')} km',
            (v) => _set(_w.copyWith(longestKm: (v * 2).round() / 2))),
        _switch(tr('Ik ben 50 of ouder'), tr('Meer herstel en een rustweek elke 3 weken.'), _w.over50, (v) => _set(_w.copyWith(over50: v))),
        _switch(tr('Ik raak snel geblesseerd'), tr('Kleinere stappen en hooguit één zware training per week.'), _w.injuryProne,
            (v) => _set(_w.copyWith(injuryProne: v))),
      ]);

  Widget _daysPage() => _page('05', tr('Wanneer loop je?'), tr('Kies je loopdagen en de dag van de lange duurloop.'), [
        _label(tr('Loopdagen')),
        _chips<int>([1, 2, 3, 4, 5, 6, 7], null, (d) => tr(_dayShort[d - 1]), (d) {
          final s = {..._w.runDays};
          s.contains(d) ? s.remove(d) : s.add(d);
          if (s.isEmpty) return;
          _set(_w.copyWith(runDays: s.toList()..sort(), longRunDay: s.contains(_w.longRunDay) ? _w.longRunDay : (s.toList()..sort()).last));
        }, isOn: (d) => _w.runDays.contains(d)),
        _label(tr('Lange duurloop op')),
        _chips<int>([..._w.runDays]..sort(), _w.longRunDay, (d) => tr(_dayLong[d - 1]), (d) => _set(_w.copyWith(longRunDay: d))),
        _label(tr('Tijd per training doordeweeks')),
        _chips<int>([30, 45, 60, 75, 90], _w.maxWeekdayMinutes, (m) => '$m min', (m) => _set(_w.copyWith(maxWeekdayMinutes: m))),
        _label(tr('Weergave')),
        _chips<bool>([false, true], _w.inMinutes, (m) => m ? tr('In minuten') : tr('In kilometers'), (m) => _set(_w.copyWith(inMinutes: m))),
      ]);

  Widget _extraPage() {
    final g = _w.goal;
    final weeks = g.isRace && _w.raceDate != null ? (_w.raceDate!.difference(DateTime.now()).inDays / 7).ceil() : _w.weeks;
    return _page('06', tr('Jouw wensen'), tr('Hoe ambitieus, en wat wil je naast het lopen?'), [
      if (!g.isStarter) ...[
        _label(tr('Ambitie')),
        for (final a in Ambition.values)
          _choice(selected: _w.ambition == a, title: tr(a.label), subtitle: tr(a.subtitle), onTap: () => _set(_w.copyWith(ambition: a))),
      ],
      _label(tr('Krachttraining per week')),
      _chips<int>([0, 1, 2], _w.strengthPerWeek, (n) => n == 0 ? tr('Geen') : '${n}×', (n) => _set(_w.copyWith(strengthPerWeek: n))),
      if (!g.isStarter) ...[
        _label(tr('Terrein')),
        _chips<Terrain>(Terrain.values, _w.terrain, (t) => tr(t.label), (t) => _set(_w.copyWith(terrain: t))),
      ],
      const SizedBox(height: 8),
      _switch(tr('Fietsen of zwemmen erbij'), tr('Crosstraining op een vrije dag.'), _w.cross, (v) => _set(_w.copyWith(cross: v))),
      _switch(tr('Ik train soms op de loopband'), tr('Tips voor tempo en intervallen op de band.'), _w.treadmill, (v) => _set(_w.copyWith(treadmill: v))),
      if (g.isRace && (g.meters ?? 0) >= 10000)
        _switch(tr('Testloop in de piekfase'), tr('Een 5 of 10 km voluit, om te zien waar je staat.'), _w.testRace, (v) => _set(_w.copyWith(testRace: v))),
      if (weeks >= 4) ...[
        _label(tr('Weken zonder lopen (vakantie)')),
        _chips<int>([for (var i = 2; i < weeks; i++) i], null, (n) => trf('wk {n}', {'n': '$n'}), (n) {
          final s = {..._w.skipWeeks};
          s.contains(n) ? s.remove(n) : s.add(n);
          _set(_w.copyWith(skipWeeks: s));
        }, isOn: (n) => _w.skipWeeks.contains(n)),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- resultaat

class _PlanResult extends StatelessWidget {
  const _PlanResult({required this.plan, required this.saving, required this.pdfBusy, required this.onSave, required this.onPdf});
  final CustomPlan plan;
  final bool saving;
  final bool pdfBusy;
  final VoidCallback onSave;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final w = plan.wishes;
    final now = DateTime.now();
    final current = plan.weeks.indexWhere((x) => !now.isBefore(x.start) && now.isBefore(x.start.add(const Duration(days: 7))));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _Hero(plan: plan),
        for (final warn in plan.warnings) _Warning(text: warn),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: _onGold, minimumSize: const Size(0, 52)),
              onPressed: pdfBusy ? null : onPdf,
              icon: pdfBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _onGold))
                  : const Icon(Icons.download_outlined, size: 20),
              label: Text(tr('Download PDF')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _gold, side: const BorderSide(color: _gold, width: 1.2), minimumSize: const Size(0, 52)),
              onPressed: saving ? null : onSave,
              icon: const Icon(Icons.event_available_outlined, size: 20),
              label: Text(tr('Zet in mijn plan')),
            ),
          ),
        ]),
        const _Section('01', 'FASES'),
        _PhaseBar(plan: plan),
        const _Section('02', 'KILOMETERS PER WEEK'),
        _VolumeBars(plan: plan),
        const _Section('03', 'JOUW TEMPO\'S'),
        _PaceTable(plan: plan),
        const _Section('04', 'WEEK VOOR WEEK'),
        for (final (i, week) in plan.weeks.indexed) _WeekCard(week: week, wishes: w, initiallyExpanded: i == (current < 0 ? 0 : current)),
        if (plan.raceDay.isNotEmpty) ...[
          const _Section('05', 'WEDSTRIJDPLAN'),
          _Panel(children: [
            for (final (i, line) in plan.raceDay.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 26,
                    child: Text((i + 1).toString().padLeft(2, '0'),
                        style: const TextStyle(fontFamily: 'KadansMono', color: _gold, fontSize: 12, height: 1.6)),
                  ),
                  Expanded(child: Text(tr(line), style: const TextStyle(color: _text, height: 1.45, fontSize: 14))),
                ]),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        Text(
          tr('Pijn die erger wordt of blijft? Stop, rust en vraag een fysiotherapeut of je huisarts. Het schema is een richtlijn, je lichaam beslist.'),
          style: const TextStyle(color: _subtle, fontSize: 12, height: 1.45),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.plan});
  final CustomPlan plan;

  @override
  Widget build(BuildContext context) {
    final w = plan.wishes;
    final title = w.raceName ?? tr(w.goal.label);
    final end = plan.raceDate ?? plan.weeks.last.start.add(const Duration(days: 6));
    final stats = <(String, String)>[
      ('${plan.weeks.length}', tr('weken')),
      ('${plan.peakKm.round()}', tr('km piekweek')),
      ('${plan.keyCount}', tr('sleuteltrainingen')),
      if (plan.predictedSeconds != null) (fmtTime(plan.predictedSeconds!), tr('verwachte tijd')) else ('${plan.totalKm.round()}', tr('km in totaal')),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(RwRadius.l),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, color: _gold),
          const SizedBox(width: 10),
          Text(tr('SCHEMA OP MAAT'), style: const TextStyle(fontFamily: 'KadansMono', fontSize: 11, letterSpacing: 1.6, color: _subtle)),
        ]),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 34, height: 1.0, color: _gold)),
        const SizedBox(height: 6),
        Text('${_date(plan.start)} – ${_date(end)} · ${tr(w.ambition.label)}', style: const TextStyle(color: _muted, fontSize: 14)),
        if (plan.goalCheck != null && w.goalTimeSeconds != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(RwRadius.s), border: Border.all(color: _goldDeep)),
            child: Text(trf('Doel {tijd} · {oordeel}', {'tijd': fmtTime(w.goalTimeSeconds!), 'oordeel': tr(plan.goalCheck!)}),
                style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          for (final (i, s) in stats.indexed) ...[
            if (i > 0) Container(width: 1, height: 34, color: _line, margin: const EdgeInsets.symmetric(horizontal: 10)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(s.$1, style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 24, color: _text, fontFeatures: rwTnum)),
                ),
                Text(s.$2, maxLines: 2, style: const TextStyle(fontSize: 11, color: _subtle, height: 1.2)),
              ]),
            ),
          ],
        ]),
        if (plan.paceIsEstimate) ...[
          const SizedBox(height: 12),
          Text(tr('Tempo\'s zijn een schatting: je hebt nog weinig runs. Loop op gevoel (zwaarte).'),
              style: const TextStyle(color: _subtle, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2116),
          borderRadius: BorderRadius.circular(RwRadius.m),
          border: Border.all(color: const Color(0xFF6B5320)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: Color(0xFFE6C16A), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(tr(text), style: const TextStyle(color: _text, fontSize: 13, height: 1.45))),
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.nr, this.title);
  final String nr;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Text('$nr  ${tr(title)}', style: const TextStyle(fontFamily: 'KadansMono', fontSize: 12, letterSpacing: 1.6, color: _subtle)),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(RwRadius.m), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.plan});
  final CustomPlan plan;

  @override
  Widget build(BuildContext context) {
    final groups = <(PlanPhase, int)>[];
    for (final w in plan.weeks) {
      if (groups.isNotEmpty && groups.last.$1 == w.phase) {
        groups[groups.length - 1] = (w.phase, groups.last.$2 + 1);
      } else {
        groups.add((w.phase, 1));
      }
    }
    final shown = <PlanPhase>{for (final g in groups) g.$1};
    return _Panel(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(RwRadius.s),
        child: Row(children: [
          for (final g in groups)
            Expanded(flex: g.$2, child: Container(height: 14, margin: const EdgeInsets.only(right: 2), color: phaseColor(g.$1))),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 14, runSpacing: 8, children: [
        for (final p in shown)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, color: phaseColor(p)),
            const SizedBox(width: 6),
            Text(tr(p.label), style: const TextStyle(color: _muted, fontSize: 12)),
          ]),
      ]),
    ]);
  }
}

class _VolumeBars extends StatelessWidget {
  const _VolumeBars({required this.plan});
  final CustomPlan plan;

  @override
  Widget build(BuildContext context) {
    final peak = plan.peakKm <= 0 ? 1.0 : plan.peakKm;
    return _Panel(children: [
      SizedBox(
        height: 96,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final w in plan.weeks)
            Expanded(
              child: Tooltip(
                message: trf('Week {n}: {km} km', {'n': '${w.number}', 'km': w.km.toStringAsFixed(0)}),
                child: Container(
                  height: 4 + 88 * (w.km / peak),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: w.recovery || w.phase == PlanPhase.vrij ? _line : phaseColor(w.phase),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text(tr('week 1'), style: const TextStyle(color: _subtle, fontSize: 11)),
        const Spacer(),
        Text(trf('piek {km} km', {'km': plan.peakKm.toStringAsFixed(0)}), style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(trf('week {n}', {'n': '${plan.weeks.length}'}), style: const TextStyle(color: _subtle, fontSize: 11)),
      ]),
    ]);
  }
}

class _PaceTable extends StatelessWidget {
  const _PaceTable({required this.plan});
  final CustomPlan plan;

  @override
  Widget build(BuildContext context) => _Panel(children: [
        for (final (i, z) in plan.paces.indexed) ...[
          if (i > 0) const Divider(height: 18, color: _line),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 4, height: 34, color: [const Color(0xFF8CC99A), const Color(0xFF8FB3D9), const Color(0xFFE6C16A), _gold, const Color(0xFFEF7F78)][i]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(z.name), style: const TextStyle(color: _text, fontWeight: FontWeight.w700)),
                Text(tr(z.text), style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${fmtPace(z.from)}–${fmtPace(z.to)}',
                  style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 17, color: _gold, fontFeatures: rwTnum)),
              Text(trf('/km · zwaarte {r}', {'r': z.rpe}), style: const TextStyle(color: _subtle, fontSize: 11)),
            ]),
          ]),
        ],
      ]);
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week, required this.wishes, required this.initiallyExpanded});
  final PlanWeek week;
  final PlanWishes wishes;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final entries = <(DateTime, Widget)>[
      for (final it in week.items) (it.session.date, _RunRow(item: it)),
      for (final e in week.extras) (e.date, _ExtraRow(extra: e)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: _surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RwRadius.m), side: const BorderSide(color: _line)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: _gold,
          collapsedIconColor: _subtle,
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(children: [
            Text(week.number.toString().padLeft(2, '0'),
                style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 22, color: _gold, fontFeatures: rwTnum)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 7, height: 7, color: phaseColor(week.phase)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      week.recovery && week.phase != PlanPhase.herstel ? '${tr(week.phase.label)} · ${tr('rustweek')}' : tr(week.phase.label),
                      style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ]),
                Text('${_date(week.start)} · ${week.km.toStringAsFixed(0)} km · ${_hours(week.minutes)}',
                    style: const TextStyle(color: _subtle, fontSize: 12)),
              ]),
            ),
          ]),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(tr(week.focus), style: const TextStyle(color: _muted, fontSize: 13, height: 1.45, fontStyle: FontStyle.italic)),
              ),
            ),
            for (final e in entries) e.$2,
          ],
        ),
      ),
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.item});
  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    final s = item.session;
    final c = kindColor(s.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(RwRadius.s),
      onTap: () => _details(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 52,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_dayShort[s.date.weekday - 1].toUpperCase(), style: const TextStyle(fontFamily: 'KadansMono', fontSize: 11, color: _subtle)),
              Text('${s.date.day}', style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 18, color: _text)),
            ]),
          ),
          Container(width: 3, height: 34, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 14))),
                if (item.key) ...[const SizedBox(width: 6), const Icon(Icons.star, size: 12, color: _gold)],
              ]),
              Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${item.minutes}′', style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w700, color: _text, fontFeatures: rwTnum)),
            Text('${item.rpe}/10', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  void _details(BuildContext context) {
    final s = item.session;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_dayLong[s.date.weekday - 1]} ${s.date.day} ${_months[s.date.month - 1]}'.toUpperCase(),
                style: const TextStyle(fontFamily: 'KadansMono', fontSize: 11, letterSpacing: 1.4, color: _subtle)),
            const SizedBox(height: 8),
            Text(s.title, style: const TextStyle(fontFamily: RwFonts.display, fontWeight: FontWeight.w800, fontSize: 24, color: _gold)),
            const SizedBox(height: 6),
            Text(trf('{min} min · zwaarte {r}/10{tempo}', {
              'min': '${item.minutes}',
              'r': '${item.rpe}',
              'tempo': s.targetPace == null ? '' : ' · ${fmtPace(s.targetPace!)} /km',
            }), style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            for (final (i, p) in item.parts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700))),
                  Expanded(child: Text(p, style: const TextStyle(color: _text, height: 1.45))),
                ]),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(RwRadius.m)),
              child: Text(trf('Waarom: {tekst}', {'tekst': item.why}), style: const TextStyle(color: _muted, height: 1.45, fontSize: 13)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({required this.extra});
  final PlanExtra extra;

  @override
  Widget build(BuildContext context) {
    final isRest = extra.kind == ExtraKind.rust;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 52,
          child: Text(_dayShort[extra.date.weekday - 1].toUpperCase(), style: const TextStyle(fontFamily: 'KadansMono', fontSize: 11, color: _subtle)),
        ),
        Icon(
          switch (extra.kind) {
            ExtraKind.kracht => Icons.fitness_center,
            ExtraKind.cross => Icons.pool_outlined,
            ExtraKind.mobiliteit => Icons.self_improvement,
            ExtraKind.rust => Icons.bedtime_outlined,
          },
          size: 16,
          color: isRest ? _subtle : _goldDeep,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(extra.title, style: TextStyle(color: isRest ? _subtle : _muted, fontWeight: FontWeight.w600, fontSize: 13)),
            if (!isRest) Text(extra.description, style: const TextStyle(color: _subtle, fontSize: 12, height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}
