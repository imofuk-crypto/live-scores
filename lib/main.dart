import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ===== الألوان =====
const bg = Color(0xFF0A2A20);
const panel = Color(0xFF0F3A2C);
const line = Color(0xFF1C5040);
const acc = Color(0xFFFFD23F);
const liveRed = Color(0xFFFF4D4D);
const mute = Color(0xFF9DBCAE);

// ===== البطولات (تكدر تضيف أو تحذف) =====
const leagues = <List<String>>[
  ['uefa.champions', 'دوري أبطال أوروبا'],
  ['eng.1', 'الدوري الإنجليزي'],
  ['esp.1', 'الدوري الإسباني'],
  ['ita.1', 'الدوري الإيطالي'],
  ['ger.1', 'الدوري الألماني'],
  ['fra.1', 'الدوري الفرنسي'],
  ['ksa.1', 'الدوري السعودي'],
  ['uefa.europa', 'الدوري الأوروبي'],
  ['afc.champions', 'أبطال آسيا'],
  ['por.1', 'الدوري البرتغالي'],
  ['ned.1', 'الدوري الهولندي'],
  ['eng.fa', 'كأس الاتحاد الإنجليزي'],
];

// مصدر البيانات: واجهة ESPN غير الرسمية (للتجربة).
// للنشر على Google Play بدّلها بـ API رسمي مثل API-Football.
const api = 'https://site.api.espn.com/apis/site/v2/sports/soccer/';
const weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'نتائج مباشرة',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: acc, surface: panel),
        ),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      );
}

// ===== النماذج =====
class Game {
  final dynamic e;
  Game(this.e);
  dynamic get c => (e['competitions'] as List).first;
  List get comps => c['competitors'] as List;
  dynamic get home => comps.firstWhere((x) => x['homeAway'] == 'home', orElse: () => comps.first);
  dynamic get away => comps.firstWhere((x) => x['homeAway'] == 'away', orElse: () => comps.last);
  String get id => '${e['id']}';
  String get state => '${e['status']?['type']?['state'] ?? 'pre'}';
  String get statusName => '${e['status']?['type']?['name'] ?? ''}';
  DateTime get date => (DateTime.tryParse('${e['date']}') ?? DateTime.now()).toLocal();
  bool get isLive => state == 'in';
  String get statusText {
    if (state == 'in') {
      return statusName == 'STATUS_HALFTIME' ? 'استراحة' : '${e['status']?['displayClock'] ?? 'مباشر'}';
    }
    if (state == 'post') return statusName == 'STATUS_POSTPONED' ? 'مؤجلة' : 'انتهت';
    return hm(date);
  }
}

class League {
  final String id, name;
  final String? logo;
  final List<Game> matches;
  League(this.id, this.name, this.logo, this.matches);
}

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String ymd(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}';
String teamName(dynamic t) => '${t['team']?['shortDisplayName'] ?? t['team']?['displayName'] ?? ''}';

Widget logo(String? url, double size) => (url == null || url.isEmpty)
    ? SizedBox(width: size, height: size)
    : Image.network(url, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size));

// ===== الشاشة الرئيسية =====
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int day = 0;
  String filter = 'all';
  List<League> data = [];
  Set<String> favs = {};
  bool loading = true;
  String? error;
  DateTime? updated;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      setState(() => favs = (p.getStringList('favs') ?? []).toSet());
    });
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  DateTime dayDate(int o) => DateTime.now().add(Duration(days: o));
  String dayLabel(int o) {
    if (o == 0) return 'اليوم';
    if (o == -1) return 'أمس';
    if (o == 1) return 'غداً';
    final d = dayDate(o);
    return '${weekdays[d.weekday - 1]} ${d.day}/${d.month}';
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) setState(() => loading = true);
    final d = ymd(dayDate(day));
    final results = await Future.wait(leagues.map((l) async {
      try {
        final r = await http.get(Uri.parse('$api${l[0]}/scoreboard?dates=$d')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return null;
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final lgs = j['leagues'] as List?;
        String? lg;
        if (lgs != null && lgs.isNotEmpty) {
          final logos = lgs.first['logos'] as List?;
          if (logos != null && logos.isNotEmpty) lg = '${logos.first['href']}';
        }
        final evs = (j['events'] as List? ?? []).map((e) => Game(e)).toList();
        return League(l[0], l[1], lg, evs);
      } catch (_) {
        return null;
      }
    }));
    final ok = results.whereType<League>().toList();
    if (!mounted) return;
    setState(() {
      loading = false;
      if (ok.isEmpty && data.isEmpty) {
        error = 'ما كدرت أوصل للنتائج. تأكد من الإنترنت واسحب للتحديث.';
      } else if (ok.isNotEmpty) {
        error = null;
        data = ok;
        updated = DateTime.now();
      }
    });
  }

  Future<void> toggleFav(String id) async {
    setState(() => favs.contains(id) ? favs.remove(id) : favs.add(id));
    final p = await SharedPreferences.getInstance();
    await p.setStringList('favs', favs.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B3D2E),
        title: const Text.rich(TextSpan(children: [
          TextSpan(text: 'نتائج ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: 'مباشرة', style: TextStyle(fontWeight: FontWeight.w800, color: acc)),
        ])),
        actions: [
          if (updated != null)
            Center(child: Text('آخر تحديث ${hm(updated!)}', style: const TextStyle(fontSize: 12, color: mute))),
          IconButton(onPressed: () => load(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Container(
          color: const Color(0xFF0B3D2E),
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [for (var o = -3; o <= 3; o++) dateChip(o)],
          ),
        ),
        Row(children: [
          tab('all', 'الكل'),
          tab('live', 'مباشر الآن'),
          tab('fav', 'المفضلة ★'),
        ]),
        Expanded(child: body()),
      ]),
    );
  }

  Widget dateChip(int o) {
    final on = o == day;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(dayLabel(o)),
        selected: on,
        showCheckmark: false,
        selectedColor: acc,
        backgroundColor: panel,
        labelStyle: TextStyle(color: on ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
        onSelected: (_) {
          setState(() {
            day = o;
            data = [];
          });
          load();
        },
      ),
    );
  }

  Widget tab(String f, String label) => Expanded(
        child: InkWell(
          onTap: () => setState(() => filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: filter == f ? acc : Colors.transparent, width: 2))),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: filter == f ? Colors.white : mute, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget body() {
    if (loading && data.isEmpty) return const Center(child: CircularProgressIndicator(color: acc));
    if (error != null) return msg(error!);
    final sections = <Widget>[];
    for (final lg in data) {
      var ms = lg.matches.toList();
      if (filter == 'live') ms = ms.where((m) => m.isLive).toList();
      if (filter == 'fav') {
        ms = ms.where((m) => favs.contains('${m.home['team']['id']}') || favs.contains('${m.away['team']['id']}')).toList();
      }
      if (ms.isEmpty) continue;
      ms.sort((a, b) {
        final l = (a.isLive ? 0 : 1) - (b.isLive ? 0 : 1);
        return l != 0 ? l : a.date.compareTo(b.date);
      });
      sections.add(leagueCard(lg, ms));
    }
    if (sections.isEmpty) {
      return msg(filter == 'live'
          ? 'ماكو مباريات مباشرة هسه.'
          : filter == 'fav'
              ? 'ما عندك فرق مفضلة بهذا اليوم. اضغط ★ جنب أي فريق.'
              : 'ماكو مباريات بهذا اليوم بالدوريات المختارة.');
    }
    return RefreshIndicator(
      color: acc,
      onRefresh: () => load(silent: true),
      child: ListView(padding: const EdgeInsets.all(10), children: sections),
    );
  }

  Widget msg(String t) => RefreshIndicator(
        onRefresh: () => load(),
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(50),
            child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: mute)),
          )
        ]),
      );

  Widget leagueCard(League lg, List<Game> ms) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              logo(lg.logo, 20),
              const SizedBox(width: 8),
              Expanded(child: Text(lg.name, style: const TextStyle(fontWeight: FontWeight.w800))),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: mute, side: const BorderSide(color: line), visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => StandingsPage(id: lg.id, name: lg.name))),
                child: const Text('الترتيب', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          for (final m in ms) matchTile(m),
        ]),
      );

  Widget teamSide(dynamic t, bool isAway) {
    final id = '${t['team']['id']}';
    final kids = <Widget>[
      GestureDetector(
        onTap: () => toggleFav(id),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.star, size: 18, color: favs.contains(id) ? acc : mute.withOpacity(.5)),
        ),
      ),
      logo('${t['team']['logo'] ?? ''}', 26),
      const SizedBox(width: 6),
      Flexible(
        child: Text(teamName(t),
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    ];
    return Row(
      mainAxisAlignment: isAway ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isAway ? kids.reversed.toList() : kids,
    );
  }

  Widget matchTile(Game m) => InkWell(
        onTap: () => showDetails(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
          child: Row(children: [
            Expanded(child: teamSide(m.home, false)),
            SizedBox(width: 92, child: scoreBox(m, 22)),
            Expanded(child: teamSide(m.away, true)),
          ]),
        ),
      );

  Widget scoreBox(Game m, double size) {
    if (m.state == 'pre') {
      return Text(hm(m.date),
          textAlign: TextAlign.center, style: TextStyle(color: acc, fontWeight: FontWeight.w800, fontSize: size * .8));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${m.home['score']} - ${m.away['score']}',
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w800)),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (m.isLive) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.circle, size: 7, color: liveRed)),
        Text(m.statusText,
            style: TextStyle(
                fontSize: 11, color: m.isLive ? liveRed : mute, fontWeight: m.isLive ? FontWeight.w800 : FontWeight.normal)),
      ]),
    ]);
  }

  void showDetails(Game m) {
    final details = (m.c['details'] as List?) ?? [];
    final homeId = '${m.home['team']['id']}';
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .6,
          maxChildSize: .9,
          builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: bigTeam(m.home)),
              scoreBox(m, 36),
              Expanded(child: bigTeam(m.away)),
            ]),
            if (m.c['venue']?['fullName'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('🏟 ${m.c['venue']['fullName']}', textAlign: TextAlign.center, style: const TextStyle(color: mute)),
              ),
            const SizedBox(height: 16),
            const Text('أحداث المباراة', style: TextStyle(fontWeight: FontWeight.w800)),
            if (details.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('ماكو أحداث مسجلة لحد الآن.', style: TextStyle(color: mute))),
            for (final d in details) eventRow(d, homeId, m),
          ]),
        ),
      ),
    );
  }

  Widget bigTeam(dynamic t) => Column(children: [
        logo('${t['team']['logo'] ?? ''}', 52),
        const SizedBox(height: 6),
        Text('${t['team']['displayName'] ?? ''}', textAlign: TextAlign.center),
      ]);

  Widget eventRow(dynamic d, String homeId, Game m) {
    final icon = d['redCard'] == true
        ? '🟥'
        : d['yellowCard'] == true
            ? '🟨'
            : d['scoringPlay'] == true
                ? '⚽'
                : '•';
    final who = ((d['athletesInvolved'] as List?) ?? []).map((a) => '${a['displayName']}').join('، ');
    final side = '${d['team']?['id']}' == homeId ? teamName(m.home) : teamName(m.away);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: Row(children: [
        SizedBox(
            width: 48,
            child: Text('${d['clock']?['displayValue'] ?? ''}', style: const TextStyle(color: acc, fontWeight: FontWeight.w800))),
        Expanded(child: Text('$icon ${who.isEmpty ? (d['type']?['text'] ?? '') : who}  ($side)')),
      ]),
    );
  }
}

// ===== شاشة الترتيب =====
class StandingsPage extends StatelessWidget {
  final String id, name;
  const StandingsPage({super.key, required this.id, required this.name});

  Future<List<dynamic>> fetch() async {
    final r = await http
        .get(Uri.parse('https://site.api.espn.com/apis/v2/sports/soccer/$id/standings'))
        .timeout(const Duration(seconds: 15));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final ch = j['children'] as List?;
    return (ch != null && ch.isNotEmpty) ? ch : [j];
  }

  String stat(dynamic en, String k) {
    for (final s in (en['stats'] as List? ?? [])) {
      if (s['name'] == k) return '${s['displayValue'] ?? ''}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFF0B3D2E), title: Text('ترتيب $name')),
        body: FutureBuilder<List<dynamic>>(
          future: fetch(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: acc));
            }
            if (snap.hasError || snap.data == null) {
              return const Center(child: Text('ما كدرت أجيب الترتيب.', style: TextStyle(color: mute)));
            }
            final groups = snap.data!;
            return ListView(padding: const EdgeInsets.all(10), children: [
              for (final g in groups) ...table(g, groups.length > 1),
            ]);
          },
        ),
      );

  List<Widget> table(dynamic g, bool showName) {
    final ents = ((g['standings']?['entries'] as List?) ?? []).toList();
    ents.sort((a, b) => (int.tryParse(stat(a, 'rank')) ?? 0).compareTo(int.tryParse(stat(b, 'rank')) ?? 0));
    if (ents.isEmpty) return [const Text('الترتيب غير متوفر لهذي البطولة.', style: TextStyle(color: mute))];
    const h = TextStyle(color: mute, fontSize: 12);
    Widget cell(String t, {TextStyle? s, double w = 30}) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: s ?? const TextStyle(fontSize: 13)));
    return [
      if (showName) Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      Row(children: [
        cell('#', s: h, w: 26),
        const Expanded(child: Text('الفريق', style: h)),
        cell('لعب', s: h), cell('ف', s: h), cell('ت', s: h), cell('خ', s: h), cell('+/-', s: h, w: 36), cell('نقاط', s: h, w: 36),
      ]),
      const Divider(color: line),
      for (var i = 0; i < ents.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
          child: Row(children: [
            cell(stat(ents[i], 'rank').isEmpty ? '${i + 1}' : stat(ents[i], 'rank'), w: 26),
            Expanded(
              child: Row(children: [
                logo(((ents[i]['team']['logos'] as List?)?.isNotEmpty ?? false) ? '${ents[i]['team']['logos'][0]['href']}' : null, 18),
                const SizedBox(width: 6),
                Flexible(child: Text(teamName(ents[i]), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              ]),
            ),
            cell(stat(ents[i], 'gamesPlayed')),
            cell(stat(ents[i], 'wins')),
            cell(stat(ents[i], 'ties')),
            cell(stat(ents[i], 'losses')),
            SizedBox(width: 36, child: Text(stat(ents[i], 'pointDifferential'), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13))),
            cell(stat(ents[i], 'points'), w: 36, s: const TextStyle(color: acc, fontWeight: FontWeight.w800)),
          ]),
        ),
    ];
  }
}
