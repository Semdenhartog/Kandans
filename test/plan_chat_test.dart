import 'package:flutter_test/flutter_test.dart';
import 'package:runwise/domain/custom_plan.dart';
import 'package:runwise/domain/plan_chat.dart';

void main() {
  final now = DateTime(2026, 11, 13);

  test('herkent een verzoek om een schema, maar geen losse vraag over een schema', () {
    expect(PlanChat.wantsPlan('Maak een schema voor mij'), isTrue);
    expect(PlanChat.wantsPlan('Ik wil graag een trainingsplan voor de halve marathon'), isTrue);
    expect(PlanChat.wantsPlan('Kun je een schema bouwen?'), isTrue);
    expect(PlanChat.wantsPlan('Is mijn schema nog goed?'), isFalse);
    expect(PlanChat.wantsPlan('Hoe ging mijn week?'), isFalse);
  });

  test('stopwoorden', () {
    expect(PlanChat.isStop('stop'), isTrue);
    expect(PlanChat.isStop('Laat maar.'), isTrue);
    expect(PlanChat.isStop('stop ik beter met lopen bij pijn?'), isFalse);
  });

  test('doelen', () {
    expect(PlanChat.parseGoal('halve marathon'), PlanGoal.halve);
    expect(PlanChat.parseGoal('marathon'), PlanGoal.marathon);
    expect(PlanChat.parseGoal('10 km'), PlanGoal.k10);
    expect(PlanChat.parseGoal('5 km'), PlanGoal.k5);
    expect(PlanChat.parseGoal('15 km'), PlanGoal.k15);
    expect(PlanChat.parseGoal('ik wil beginnen met lopen'), PlanGoal.beginnen);
    expect(PlanChat.parseGoal('sneller worden'), PlanGoal.sneller);
    expect(PlanChat.parseGoal('fit blijven'), PlanGoal.fit);
    expect(PlanChat.parseGoal('terugkomen'), PlanGoal.terugkomen);
    expect(PlanChat.parseGoal('pannenkoeken'), isNull);
  });

  test('datums', () {
    expect(PlanChat.parseRaceDate('over 12 weken', now, 10), DateTime(2027, 2, 5));
    expect(PlanChat.parseRaceDate('14-3-2027', now, 10), DateTime(2027, 3, 14));
    expect(PlanChat.parseRaceDate('14-3', now, 10), DateTime(2027, 3, 14));
    expect(PlanChat.parseRaceDate('20 december', now, 10), DateTime(2026, 12, 20));
    expect(PlanChat.parseRaceDate('14 maart 2027', now, 10), DateTime(2027, 3, 14));
    expect(PlanChat.parseRaceDate('nog geen datum', now, 10), DateTime(2027, 1, 22));
    expect(PlanChat.parseRaceDate('31-2-2027', now, 10), isNull);
    expect(PlanChat.parseRaceDate('ergens in de lente', now, 10), isNull);
  });

  test('kilometers, dagen en 5 km-tijd', () {
    expect(PlanChat.parseKm('15 tot 30 km'), 22.5);
    expect(PlanChat.parseKm('meer dan 50 km'), closeTo(55, 0.01));
    expect(PlanChat.parseKm('8 km'), 8);
    expect(PlanChat.parseKm('21 km of meer'), 21);
    expect(PlanChat.parseKm('geen idee'), isNull);
    expect(PlanChat.parseDays('ma wo za'), [1, 3, 6]);
    expect(PlanChat.parseDays('dinsdag, donderdag en zondag'), [2, 4, 7]);
    expect(PlanChat.parseDays('zo di'), [2, 7]);
    expect(PlanChat.parseDays('doe maar wat'), isEmpty);
    expect(PlanChat.parseFiveK('27:30'), 1650);
    expect(PlanChat.parseFiveK('27'), 1620);
    expect(PlanChat.parseFiveK('5:00'), isNull);
  });

  test('heel gesprek voor een 10 km geeft een schema', () {
    final chat = PlanChat(now: now);
    expect(chat.start().options, contains('10 km'));
    expect(chat.answer('10 km').text, contains('Wanneer'));
    expect(chat.answer('over 10 weken').text, contains('per week'));
    expect(chat.answer('15 tot 30 km').text, contains('langste'));
    expect(chat.answer('8 km').text, contains('dagen'));
    expect(chat.answer('di do zo').text, contains('ambitieus'));
    expect(chat.answer('Gebalanceerd: stevig maar haalbaar').text, contains('5 km'));
    expect(chat.answer('Weet ik niet').text, isEmpty);
    expect(chat.done, isTrue);

    final w = chat.wishes;
    expect(w.goal, PlanGoal.k10);
    expect(w.raceDate, DateTime(2027, 1, 22));
    expect(w.weeklyKm, 22.5);
    expect(w.longestKm, 8);
    expect(w.runDays, [2, 4, 7]);
    expect(w.longRunDay, 7);
    expect(w.ambition, Ambition.gebalanceerd);
    expect(w.recent5kSeconds, isNull);

    final plan = buildCustomPlan(w, start: now.add(const Duration(days: 1)));
    expect(plan.weeks, isNotEmpty);
    final text = planChatSummary(plan);
    expect(text, contains('Je schema is klaar: 10 km'));
    expect(text, contains('dinsdag, donderdag, zondag'));
    expect(text, contains('Je eerste week:'));
  });

  test('beginner krijgt alleen doel en dagen; bekende cijfers uit het logboek worden overgeslagen', () {
    final starter = PlanChat(now: now)..start();
    expect(starter.answer('Beginnen').text, contains('dagen'));
    expect(starter.answer('ma wo za').text, isEmpty);
    expect(starter.done, isTrue);
    expect(starter.wishes.runDays, [1, 3, 6]);
    expect(buildCustomPlan(starter.wishes, start: now).weeks, isNotEmpty);

    final known = PlanChat(now: now, weeklyKm: 24, longestKm: 12)..start();
    expect(known.answer('fit blijven').text, contains('dagen'));
    expect(known.wishes.weeklyKm, 24);
    expect(known.wishes.longestKm, 12);
  });

  test('onbegrepen antwoord herhaalt de vraag en gaat niet verder', () {
    final chat = PlanChat(now: now)..start();
    final again = chat.answer('pannenkoeken');
    expect(again.text, contains('herken ik niet'));
    expect(again.options, contains('Marathon'));
    expect(chat.step, PlanChatStep.goal);
    chat.answer('marathon');
    expect(chat.answer('morgen').text, contains('begrijp ik niet'));
    expect(chat.answer('1-1-2030').text, contains('meer dan een jaar'));
    expect(chat.step, PlanChatStep.race);
  });
}
