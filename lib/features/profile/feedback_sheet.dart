import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/error_reporter.dart';
import '../../core/theme.dart';

/// Feedback sturen: een paar woorden plus (op verzoek) de appversie en het toestel, zodat een fout terug te vinden is.
Future<void> showFeedbackSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: RwColors.surface,
      builder: (_) => const _FeedbackSheet(),
    );

/// Technische regel onder de feedback.
String feedbackFooter() {
  String os;
  try {
    os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    os = 'onbekend toestel';
  }
  return 'Kadans ${ErrorReporter.appVersion} · $os';
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _text = TextEditingController();
  String _kind = 'Idee';
  bool _withInfo = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = [
      _text.text.trim(),
      if (_withInfo) '\n— ${feedbackFooter()}',
    ].join('\n');
    final subject = 'Kadans feedback: $_kind';
    final nav = Navigator.of(context);
    var sent = false;
    if (AppConfig.feedbackEmail.isNotEmpty) {
      sent = await launchUrl(
        Uri(scheme: 'mailto', path: AppConfig.feedbackEmail, query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}'),
        mode: LaunchMode.externalApplication,
      ).catchError((Object _) => false);
    }
    if (!sent) await SharePlus.instance.share(ShareParams(text: body, subject: subject));
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Feedback sturen', style: RwText.title),
          const SizedBox(height: 6),
          Text('Wat kan beter, wat werkt niet, of wat vind je top? Elk berichtje helpt.',
              style: TextStyle(color: RwColors.muted, height: 1.4)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final k in const ['Idee', 'Iets werkt niet', 'Compliment'])
              ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _kind == 'Iets werkt niet' ? 'Wat deed je, en wat ging er mis?' : 'Typ je bericht…',
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _withInfo,
            onChanged: (v) => setState(() => _withInfo = v),
            title: const Text('Appversie en toestel meesturen'),
            subtitle: Text(feedbackFooter(), style: TextStyle(color: RwColors.subtle, fontSize: 12)),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _text.text.trim().isEmpty ? null : _send,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Versturen'),
          ),
          const SizedBox(height: 6),
          Text('Je kiest zelf hoe je het verstuurt (mail, WhatsApp…). Er gaan geen andere gegevens mee.',
              textAlign: TextAlign.center, style: TextStyle(color: RwColors.subtle, fontSize: 12)),
        ]),
      ),
    );
  }
}
