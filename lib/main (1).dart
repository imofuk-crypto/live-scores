import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ===== ألوان العلم العراقي =====
const bg = Color(0xFF0D0D0D); // أسود
const panel = Color(0xFF1A1A1A);
const line = Color(0xFF2C2C2C);
const red = Color(0xFFCE1126); // أحمر
const green = Color(0xFF00A651); // أخضر
const white = Color(0xFFFFFFFF);
const mute = Color(0xFF9A9A9A);

const appName = 'هدف';

// ===== البطولات (تكدر تضيف أو تحذف) =====
// الدوري العراقي والمصري غير متوفرين بمصدر البيانات الحالي.
const leagues = <List<String>>[
  ['fifa.world', 'كأس العالم'],
  ['fifa.worldq.afc', 'تصفيات آسيا لكأس العالم'],
  ['uefa.champions', 'دوري أبطال أوروبا'],
  ['eng.1', 'الدوري الإنجليزي'],
  ['esp.1', 'الدوري الإسباني'],
  ['ita.1', 'الدوري الإيطالي'],
  ['ger.1', 'الدوري الألماني'],
  ['fra.1', 'الدوري الفرنسي'],
  ['ksa.1', 'الدوري السعودي'],
  ['afc.champions', 'أبطال آسيا للنخبة'],
  ['afc.asian.cup', 'كأس آسيا'],
  ['uefa.europa', 'الدوري الأوروبي'],
  ['uefa.europa.conf', 'دوري المؤتمر'],
  ['uefa.nations', 'دوري الأمم الأوروبية'],
  ['por.1', 'الدوري البرتغالي'],
  ['ned.1', 'الدوري الهولندي'],
  ['tur.1', 'الدوري التركي'],
  ['usa.1', 'الدوري الأمريكي'],
  ['eng.fa', 'كأس الاتحاد الإنجليزي'],
  ['eng.league_cup', 'كأس الرابطة الإنجليزية'],
  ['esp.copa_del_rey', 'كأس ملك إسبانيا'],
  ['ita.coppa_italia', 'كأس إيطاليا'],
  ['ger.dfb_pokal', 'كأس ألمانيا'],
  ['fra.coupe_de_france', 'كأس فرنسا'],
];

// مصدر البيانات: واجهة ESPN غير الرسمية (للتجربة).
const api = 'https://site.api.espn.com/apis/site/v2/sports/soccer/';
const weekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

const statNames = {
  'possessionPct': 'الاستحواذ %',
  'totalShots': 'التسديدات',
  'shotsOnTarget': 'على المرمى',
  'wonCorners': 'الركنيات',
  'foulsCommitted': 'الأخطاء',
  'yellowCards': 'بطاقات صفراء',
  'redCards': 'بطاقات حمراء',
  'offsides': 'التسلل',
  'saves': 'التصديات',
  'totalPasses': 'التمريرات',
  'accuratePasses': 'تمريرات صحيحة',
  'passPct': 'دقة التمرير',
  'totalTackles': 'الافتكاك',
  'effectiveTackles': 'افتكاك ناجح',
  'totalCrosses': 'العرضيات',
  'interceptions': 'قطع الكرة',
  'totalClearance': 'الإبعادات',
  'blockedShots': 'تسديدات مصدودة',
  'totalLongBalls': 'كرات طويلة',
};
const posNames = {'G': 'حارس', 'D': 'مدافع', 'M': 'وسط', 'F': 'مهاجم'};

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: appName,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: green, secondary: red, surface: panel),
          appBarTheme: const AppBarTheme(backgroundColor: red, foregroundColor: white, centerTitle: false),
        ),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Home(),
      );
}

// شريط العلم تحت العنوان
class FlagBar extends StatelessWidget implements PreferredSizeWidget {
  const FlagBar({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(6);
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(height: 2, color: red),
        Container(height: 2, color: white),
        Container(height: 2, color: Colors.black),
      ]);
}

// ===== النماذج =====
class Game {
  final dynamic e;
  final String leagueId, leagueName;
  Game(this.e, this.leagueId, this.leagueName);
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
String dm(DateTime d) => '${d.day}/${d.month}/${d.year}';
String teamName(dynamic t) => '${t['team']?['shortDisplayName'] ?? t['team']?['displayName'] ?? ''}';

Widget logo(String? url, double size) => (url == null || url.isEmpty || url == 'null')
    ? SizedBox(width: size, height: size)
    : Image.network(url, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => SizedBox(width: size, height: size));

Widget emptyMsg(String t) =>
    Padding(padding: const EdgeInsets.all(40), child: Text(t, textAlign: TextAlign.center, style: const TextStyle(color: mute)));

Widget card({required Widget child, EdgeInsets? margin}) => Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

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
      if (mounted) setState(() => favs = (p.getStringList('favs') ?? []).toSet());
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
        final evs = (j['events'] as List? ?? []).map((e) => Game(e, l[0], l[1])).toList();
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
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sports_soccer, size: 26),
          SizedBox(width: 8),
          Text(appName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
        ]),
        bottom: const FlagBar(),
        actions: [
          if (updated != null)
            Center(child: Text('تحديث ${hm(updated!)}', style: const TextStyle(fontSize: 12, color: Colors.white70))),
          IconButton(onPressed: () => load(), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [for (var o = -3; o <= 3; o++) dateChip(o)],
          ),
        ),
        Row(children: [tab('all', 'الكل'), tab('live', 'مباشر الآن'), tab('fav', 'المفضلة ★')]),
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
        selectedColor: green,
        backgroundColor: panel,
        side: BorderSide(color: on ? green : line),
        labelStyle: TextStyle(color: white, fontWeight: on ? FontWeight.w800 : FontWeight.w500),
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
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: filter == f ? red : line, width: filter == f ? 3 : 1))),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(color: filter == f ? white : mute, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget body() {
    if (loading && data.isEmpty) return const Center(child: CircularProgressIndicator(color: green));
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
              : 'ماكو مباريات بهذا اليوم بالبطولات المختارة.');
    }
    return RefreshIndicator(
      color: green,
      onRefresh: () => load(silent: true),
      child: ListView(padding: const EdgeInsets.all(10), children: sections),
    );
  }

  Widget msg(String t) => RefreshIndicator(onRefresh: () => load(), child: ListView(children: [emptyMsg(t)]));

  Widget leagueCard(League lg, List<Game> ms) => card(
        child: Column(children: [
          Container(
            decoration: const BoxDecoration(border: Border(right: BorderSide(color: red, width: 4))),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              logo(lg.logo, 20),
              const SizedBox(width: 8),
              Expanded(child: Text(lg.name, style: const TextStyle(fontWeight: FontWeight.w800))),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: green, side: const BorderSide(color: green), visualDensity: VisualDensity.compact),
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
          child: Icon(Icons.star, size: 18, color: favs.contains(id) ? red : mute.withValues(alpha: .4)),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchPage(game: m))),
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
}

Widget scoreBox(Game m, double size) {
  if (m.state == 'pre') {
    return Text(hm(m.date),
        textAlign: TextAlign.center, style: TextStyle(color: green, fontWeight: FontWeight.w800, fontSize: size * .8));
  }
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Text('${m.home['score']} - ${m.away['score']}',
        textDirection: TextDirection.ltr, style: TextStyle(fontSize: size, fontWeight: FontWeight.w900)),
    Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: m.isLive ? red : Colors.transparent, borderRadius: BorderRadius.circular(6)),
      child: Text(m.statusText,
          style: TextStyle(fontSize: 11, color: m.isLive ? white : mute, fontWeight: m.isLive ? FontWeight.w800 : FontWeight.normal)),
    ),
  ]);
}

// ===== شاشة المباراة =====
class MatchPage extends StatefulWidget {
  final Game game;
  const MatchPage({super.key, required this.game});
  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  dynamic summary;
  bool loading = true;
  Timer? timer;

  Game get m => widget.game;
  String get homeId => '${m.home['team']['id']}';

  @override
  void initState() {
    super.initState();
    fetch();
    if (m.isLive) timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> fetch() async {
    try {
      final r = await http
          .get(Uri.parse('$api${m.leagueId}/summary?event=${m.id}'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) summary = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(m.leagueName, style: const TextStyle(fontSize: 17)),
            bottom: const TabBar(
              isScrollable: true,
              indicatorColor: white,
              labelColor: white,
              unselectedLabelColor: Colors.white70,
              tabs: [Tab(text: 'الأحداث'), Tab(text: 'الإحصائيات'), Tab(text: 'التشكيلة'), Tab(text: 'الفورمة والمواجهات')],
            ),
          ),
          body: Column(children: [
            header(),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: green))
                  : TabBarView(children: [events(), stats(), lineups(), form()]),
            ),
          ]),
        ),
      );

  Widget header() => Container(
        color: panel,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        child: Column(children: [
          Row(children: [
            Expanded(child: bigTeam(m.home)),
            scoreBox(m, 36),
            Expanded(child: bigTeam(m.away)),
          ]),
          if (m.c['venue']?['fullName'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('🏟 ${m.c['venue']['fullName']}  ·  ${dm(m.date)}',
                  textAlign: TextAlign.center, style: const TextStyle(color: mute, fontSize: 12)),
            ),
        ]),
      );

  Widget bigTeam(dynamic t) => Column(children: [
        logo('${t['team']['logo'] ?? ''}', 54),
        const SizedBox(height: 6),
        Text('${t['team']['displayName'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  // ----- الأحداث -----
  Widget events() {
    List det = (m.c['details'] as List?) ?? [];
    final hdr = summary?['header']?['competitions'];
    if (hdr is List && hdr.isNotEmpty && hdr.first['details'] is List) det = hdr.first['details'] as List;
    if (det.isEmpty) return ListView(children: [emptyMsg('ماكو أحداث مسجلة لحد الآن.')]);
    return ListView(padding: const EdgeInsets.all(12), children: [for (final d in det) eventRow(d)]);
  }

  String athletes(dynamic d) {
    final a = (d['athletesInvolved'] as List?) ?? (d['participants'] as List?) ?? [];
    return a.map((x) => '${x['displayName'] ?? x['athlete']?['displayName'] ?? ''}').where((s) => s.isNotEmpty).join('، ');
  }

  Widget eventRow(dynamic d) {
    final isHome = '${d['team']?['id']}' == homeId;
    final icon = d['redCard'] == true
        ? '🟥'
        : d['yellowCard'] == true
            ? '🟨'
            : d['scoringPlay'] == true
                ? (d['ownGoal'] == true ? '⚽ (ذاتي)' : d['penaltyKick'] == true ? '⚽ (جزاء)' : '⚽')
                : '•';
    final who = athletes(d);
    final text = '$icon ${who.isEmpty ? (d['type']?['text'] ?? '') : who}';
    final minute = Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(8)),
      child: Text('${d['clock']?['displayValue'] ?? ''}',
          textAlign: TextAlign.center, style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: isHome ? Text(text, textAlign: TextAlign.end) : const SizedBox()),
        const SizedBox(width: 8),
        minute,
        const SizedBox(width: 8),
        Expanded(child: isHome ? const SizedBox() : Text(text)),
      ]),
    );
  }

  // ----- الإحصائيات -----
  Widget stats() {
    final teams = (summary?['boxscore']?['teams'] as List?) ?? [];
    if (teams.length < 2) return ListView(children: [emptyMsg('الإحصائيات غير متوفرة لهذي المباراة.')]);
    final h = teams.firstWhere((t) => t['homeAway'] == 'home' || '${t['team']?['id']}' == homeId, orElse: () => teams.first);
    final a = teams.firstWhere((t) => !identical(t, h), orElse: () => teams.last);
    final aMap = <String, String>{};
    for (final s in (a['statistics'] as List? ?? [])) {
      aMap['${s['name']}'] = '${s['displayValue'] ?? ''}';
    }
    final rows = <Widget>[];
    for (final s in (h['statistics'] as List? ?? [])) {
      final name = '${s['name']}';
      if (!aMap.containsKey(name)) continue;
      final label = statNames[name] ?? '${s['label'] ?? name}';
      rows.add(statRow(label, '${s['displayValue'] ?? ''}', aMap[name]!));
    }
    if (rows.isEmpty) return ListView(children: [emptyMsg('الإحصائيات غير متوفرة لهذي المباراة.')]);
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        logo('${m.home['team']['logo'] ?? ''}', 24),
        const Spacer(),
        logo('${m.away['team']['logo'] ?? ''}', 24),
      ]),
      const SizedBox(height: 8),
      ...rows,
    ]);
  }

  Widget statRow(String label, String hv, String av) {
    final h = double.tryParse(hv.replaceAll('%', '')) ?? 0;
    final a = double.tryParse(av.replaceAll('%', '')) ?? 0;
    final total = h + a;
    final hf = total == 0 ? .5 : h / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          Text(hv, style: TextStyle(fontWeight: FontWeight.w800, color: h > a ? green : white)),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: mute, fontSize: 13))),
          Text(av, style: TextStyle(fontWeight: FontWeight.w800, color: a > h ? red : white)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Row(children: [
              Expanded(flex: (hf * 1000).round().clamp(1, 999).toInt(), child: Container(color: green)),
              const SizedBox(width: 3),
              Expanded(flex: ((1 - hf) * 1000).round().clamp(1, 999).toInt(), child: Container(color: red)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ----- التشكيلة -----
  Widget lineups() {
    final rosters = (summary?['rosters'] as List?) ?? [];
    final withPlayers = rosters.where((r) => ((r['roster'] as List?) ?? []).isNotEmpty).toList();
    if (withPlayers.isEmpty) return ListView(children: [emptyMsg('التشكيلة تنزل عادةً قبل المباراة بساعة.')]);
    withPlayers.sort((x, y) => (x['homeAway'] == 'home' ? 0 : 1) - (y['homeAway'] == 'home' ? 0 : 1));
    return ListView(padding: const EdgeInsets.all(10), children: [for (final r in withPlayers) rosterCard(r)]);
  }

  Widget rosterCard(dynamic r) {
    final list = (r['roster'] as List?) ?? [];
    final starters = list.where((p) => p['starter'] == true).toList()
      ..sort((x, y) => (int.tryParse('${x['formationPlace']}') ?? 99).compareTo(int.tryParse('${y['formationPlace']}') ?? 99));
    final subs = list.where((p) => p['starter'] != true).toList();
    final logos = r['team']?['logos'] as List?;
    final isHome = r['homeAway'] == 'home';
    return card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: isHome ? green : red,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            logo(logos != null && logos.isNotEmpty ? '${logos.first['href']}' : null, 24),
            const SizedBox(width: 8),
            Expanded(child: Text('${r['team']?['displayName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (r['formation'] != null)
              Text('${r['formation']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 4), child: Text('الأساسيين', style: TextStyle(color: mute))),
        for (final p in starters) playerRow(p),
        if (subs.isNotEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('الاحتياط', style: TextStyle(color: mute))),
        for (final p in subs) playerRow(p),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget playerRow(dynamic p) {
    final pos = '${p['position']?['abbreviation'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: line, shape: BoxShape.circle),
          child: Text('${p['jersey'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('${p['athlete']?['displayName'] ?? ''}', overflow: TextOverflow.ellipsis)),
        if (p['subbedIn'] == true) const Icon(Icons.arrow_upward, size: 16, color: green),
        if (p['subbedOut'] == true) const Icon(Icons.arrow_downward, size: 16, color: red),
        const SizedBox(width: 6),
        Text(posNames[pos.isEmpty ? '' : pos[0]] ?? pos, style: const TextStyle(color: mute, fontSize: 12)),
      ]),
    );
  }

  // ----- الفورمة والمواجهات -----
  Widget form() {
    final last = (summary?['lastFiveGames'] as List?) ?? [];
    final h2h = (summary?['headToHeadGames'] as List?) ?? [];
    final widgets = <Widget>[];
    final sorted = last.toList()
      ..sort((x, y) => ('${x['team']?['id']}' == homeId ? 0 : 1) - ('${y['team']?['id']}' == homeId ? 0 : 1));
    for (final t in sorted) {
      final evs = (t['events'] as List?) ?? [];
      if (evs.isEmpty) continue;
      widgets.add(card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              logo('${t['team']?['logo'] ?? ''}', 22),
              const SizedBox(width: 8),
              Expanded(child: Text('آخر مباريات ${t['team']?['displayName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [for (final e in evs) resultChip('${e['gameResult'] ?? ''}')]),
          ),
          const SizedBox(height: 6),
          for (final e in evs) formRow(e),
          const SizedBox(height: 6),
        ]),
      ));
    }
    final h2hEvents = <dynamic>[];
    for (final g in h2h) {
      final evs = g is Map ? (g['events'] as List?) : null;
      if (evs != null) h2hEvents.addAll(evs);
    }
    if (h2hEvents.isNotEmpty) {
      widgets.add(card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.all(10), child: Text('المواجهات المباشرة', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final e in h2hEvents.take(6)) formRow(e, h2h: true),
          const SizedBox(height: 6),
        ]),
      ));
    }
    if (widgets.isEmpty) return ListView(children: [emptyMsg('ماكو بيانات فورمة لهذي المباراة.')]);
    return ListView(padding: const EdgeInsets.all(10), children: widgets);
  }

  Widget resultChip(String r) {
    final c = r == 'W' ? green : r == 'L' ? red : mute;
    final t = r == 'W' ? 'ف' : r == 'L' ? 'خ' : r == 'D' ? 'ت' : '-';
    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  Widget formRow(dynamic e, {bool h2h = false}) {
    final d = DateTime.tryParse('${e['gameDate']}')?.toLocal();
    final opp = '${e['opponent']?['displayName'] ?? ''}';
    final at = '${e['atVs'] ?? ''}' == '@' || '${e['atVs'] ?? ''}' == 'at' ? 'ضد (خارج)' : 'ضد';
    final r = '${e['gameResult'] ?? ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: line))),
      child: Row(children: [
        SizedBox(width: 74, child: Text(d == null ? '' : dm(d), style: const TextStyle(color: mute, fontSize: 12))),
        logo('${e['opponentLogo'] ?? ''}', 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(h2h ? '${e['competitionName'] ?? e['leagueName'] ?? ''}' : '$at $opp',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ),
        Text('${e['score'] ?? ''}',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontWeight: FontWeight.w800, color: r == 'W' ? green : r == 'L' ? red : white)),
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
        appBar: AppBar(title: Text('ترتيب $name'), bottom: const FlagBar()),
        body: FutureBuilder<List<dynamic>>(
          future: fetch(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: green));
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
    if (ents.isEmpty) return [emptyMsg('الترتيب غير متوفر لهذي البطولة.')];
    const h = TextStyle(color: mute, fontSize: 12);
    Widget cell(String t, {TextStyle? s, double w = 30}) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: s ?? const TextStyle(fontSize: 13)));
    return [
      if (showName)
        Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w800))),
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
            SizedBox(
                width: 36,
                child: Text(stat(ents[i], 'pointDifferential'),
                    textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13))),
            cell(stat(ents[i], 'points'), w: 36, s: const TextStyle(color: green, fontWeight: FontWeight.w800)),
          ]),
        ),
    ];
  }
}
