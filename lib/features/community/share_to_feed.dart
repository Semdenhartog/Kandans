import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/services/community_feed_service.dart' show CommunityNotReady;
import '../../data/services/community_service.dart';
import '../../data/services/social_service.dart';
import '../../domain/privacy_zone.dart';
import '../../shared/widgets.dart';
import '../challenges/community_screen.dart';
import '../routes/route_shape.dart';
import 'community_feed_screen.dart' show ensureCommunityRules;

/// Of deze eigen run gedeeld is (null = niet gedeeld).
final myShareProvider = FutureProvider.autoDispose.family<MyShare?, String>(
  (ref, activityId) => ref.watch(socialServiceProvider).shareOf(activityId),
);

/// Knop onder een run: "Delen met volgers" of "Gedeeld met …".
/// Niet bij runs uit Strava (voorwaarden van Strava).
class ShareToFeedButton extends ConsumerWidget {
  const ShareToFeedButton({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    if (a.id == null) return const SizedBox.shrink();
    if (a.viaStrava) {
      return Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(tr('Runs uit Strava kun je niet met volgers delen (voorwaarden van Strava).'),
            textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
      );
    }
    final share = ref.watch(myShareProvider(a.id!));
    // Community nog niet beschikbaar of geen verbinding: knop gewoon tonen, het blad meldt wat er mis is.
    final s = share.value;
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: () => openShareToFeed(context, a, current: s),
        icon: Icon(s == null ? Icons.group_add_outlined : (s.visibility == ShareVisibility.everyone ? Icons.public : Icons.group_outlined)),
        label: Text(s == null
            ? tr('Delen met volgers')
            : s.visibility == ShareVisibility.everyone
                ? trf('Gedeeld met iedereen · {n} applaus', {'n': s.kudos})
                : trf('Gedeeld met volgers · {n} applaus', {'n': s.kudos})),
      ),
    );
  }
}

Future<void> openShareToFeed(BuildContext context, Activity a, {MyShare? current}) async {
  final container = ProviderScope.containerOf(context);
  CommunityStatus status;
  try {
    status = await container.read(communityStatusProvider.future);
  } catch (e) {
    if (context.mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return;
  }
  if (!context.mounted) return;
  if (!status.joined) {
    final go = await confirmDialog(
      context,
      title: tr('Eerst een bijnaam kiezen'),
      message: tr('Om runs te delen doe je mee met Samen. Anderen zien alleen je bijnaam, nooit je naam of e-mail.'),
      confirmLabel: tr('Bijnaam kiezen'),
      destructive: false,
    );
    if (go && context.mounted) openCommunity(context);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShareToFeedSheet(activity: a, current: current),
  );
  container.invalidate(myShareProvider(a.id!));
}

/// Blad om een run te delen: wie mag hem zien, titel en privacyzone.
class ShareToFeedSheet extends ConsumerStatefulWidget {
  const ShareToFeedSheet({super.key, required this.activity, this.current});
  final Activity activity;
  final MyShare? current;

  @override
  ConsumerState<ShareToFeedSheet> createState() => _ShareToFeedSheetState();
}

class _ShareToFeedSheetState extends ConsumerState<ShareToFeedSheet> {
  late ShareVisibility _vis = widget.current?.visibility ?? ShareVisibility.followers;
  late final _title = TextEditingController(text: widget.current?.title ?? _defaultTitle(widget.activity));
  int _zone = privacyZoneDefault;
  bool _busy = false;

  static String _defaultTitle(Activity a) {
    final h = a.startedAt.toLocal().hour;
    final part = h < 6
        ? tr('Nachtloopje')
        : h < 12
            ? tr('Ochtendloopje')
            : h < 18
                ? tr('Middagloopje')
                : tr('Avondloopje');
    return '$part ${Fmt.km(a.distanceMeters, decimals: 1)}';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String? get _trimmed => privacyTrimmedPolyline(widget.activity.trackPolyline, meters: _zone);

  Future<void> _share() async {
    if (!await ensureCommunityRules(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialServiceProvider).shareRun(
            widget.activity.id!,
            visibility: _vis,
            title: _title.text.trim(),
            polyline: _trimmed,
          );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, widget.current == null ? tr('Gedeeld! Je volgers zien je run in hun feed.') : tr('Bijgewerkt.'));
    } on CommunityNotReady {
      if (mounted) showMessage(context, tr('Runs delen gaat binnenkort open.'), error: true);
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unshare() async {
    setState(() => _busy = true);
    try {
      await ref.read(socialServiceProvider).unshareRun(widget.activity.id!);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, tr('Je deelt deze run niet meer.'));
    } catch (e) {
      if (mounted) showMessage(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final trimmed = _trimmed;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.current == null ? tr('Run delen') : tr('Gedeelde run'), style: RwText.title),
          SizedBox(height: 4),
          Text('${Fmt.km(a.distanceMeters)} · ${Fmt.duration(a.movingTimeSeconds)} · ${Fmt.pace(a.paceSecondsPerKm)}',
              style: TextStyle(color: RwColors.muted)),
          SizedBox(height: 16),
          Text(tr('WIE MAG HEM ZIEN?'), style: RwText.overline),
          SizedBox(height: 8),
          SegmentedButton<ShareVisibility>(
            segments: [
              ButtonSegment(value: ShareVisibility.followers, icon: Icon(Icons.group_outlined), label: Text(tr('Volgers'))),
              ButtonSegment(value: ShareVisibility.everyone, icon: Icon(Icons.public), label: Text(tr('Iedereen'))),
            ],
            selected: {_vis},
            onSelectionChanged: (v) => setState(() => _vis = v.first),
          ),
          SizedBox(height: 6),
          Text(
            _vis == ShareVisibility.followers
                ? tr('Alleen lopers die jou volgen zien deze run.')
                : tr('Alle Kadans-lopers kunnen deze run zien, ook bij "Iedereen" in de feed.'),
            style: TextStyle(color: RwColors.subtle, fontSize: 12.5),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Titel')),
          ),
          if (a.hasTrack) ...[
            SizedBox(height: 4),
            Text(tr('PRIVACYZONE'), style: RwText.overline),
            SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final m in privacyZoneOptions)
                ChoiceChip(
                  label: Text(m >= 1000 ? '${m ~/ 1000} km' : '$m m'),
                  selected: _zone == m,
                  onSelected: (_) => setState(() => _zone = m),
                ),
            ]),
            SizedBox(height: 6),
            Text(trf('Rond je start en finish laten we {m} van de route weg, zodat niemand ziet waar je woont.', {'m': _zone >= 1000 ? '${_zone ~/ 1000} km' : '$_zone m'}),
                style: TextStyle(color: RwColors.subtle, fontSize: 12.5)),
            SizedBox(height: 10),
            Container(
              height: 130,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RwColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: RwColors.hairline),
              ),
              child: trimmed == null
                  ? Center(
                      child: Text(tr('Deze run is te kort om een kaart te delen. Je deelt alleen de cijfers.'),
                          textAlign: TextAlign.center, style: TextStyle(color: RwColors.muted)),
                    )
                  : ExcludeSemantics(child: RouteShape(key: ValueKey(_zone), polyline: trimmed, strokeWidth: 2.5)),
            ),
          ],
          SizedBox(height: 12),
          Text(tr('Hartslag en andere gezondheidsgegevens deel je nooit. Je kunt het delen altijd weer stoppen.'),
              style: TextStyle(color: RwColors.subtle, fontSize: 12.5)),
          SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send),
            label: Text(widget.current == null ? tr('Delen') : tr('Opslaan')),
          ),
          if (widget.current != null) ...[
            SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _unshare, child: Text(tr('Niet meer delen'), style: TextStyle(color: RwColors.danger))),
          ],
        ]),
      ),
    );
  }
}
