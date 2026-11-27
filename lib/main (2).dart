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
const playerStatNames = {
  'totalGoals': 'أهداف',
  'goalAssists': 'تمريرات حاسمة',
  'totalShots': 'تسديدات',
  'shotsOnTarget': 'على المرمى',
  'saves': 'تصديات',
  'goalsConceded': 'أهداف مستقبلة',
  'shotsFaced': 'تسديدات واجهها',
  'foulsCommitted': 'أخطاء ارتكبها',
  'foulsSuffered': 'أخطاء عليه',
  'offsides': 'تسلل',
  'yellowCards': 'بطاقات صفراء',
  'redCards': 'بطاقات حمراء',
  'ownGoals': 'أهداف ذاتية',
};
const eventNames = {
  'Kickoff': 'بداية المباراة',
  'Halftime': 'نهاية الشوط الأول',
  'Start 2nd Half': 'بداية الشوط الثاني',
  'End Regular Time': 'نهاية الوقت الأصلي',
  'Full Time': 'نهاية المباراة',
  'Start Extra Time': 'بداية الوقت الإضافي',
  'End Extra Time': 'نهاية الوقت الإضافي',
  'Start Shootout': 'ركلات الترجيح',
};

String lastName(String n) {
  final parts = n.trim().split(' ');
  return parts.length > 1 ? parts.sublist(1).join(' ') : n;
}

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
      final r = await http.get(Uri.parse('$api${m.leagueId}/summary?event=${m.id}')).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) summary = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  // النتيجة الحية من الملخص إذا متوفرة
  List get headerComps {
    final c = summary?['header']?['competitions'];
    if (c is List && c.isNotEmpty && c.first['competitors'] is List) return c.first['competitors'] as List;
    return m.comps;
  }

  String scoreOf(String side) {
    for (final t in headerComps) {
      if (t['homeAway'] == side) return '${t['score'] ?? ''}';
    }
    return side == 'home' ? '${m.home['score']}' : '${m.away['score']}';
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: Text(m.leagueName, style: const TextStyle(fontSize: 17)),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: white,
              labelColor: white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(text: 'المباراة'),
                Tab(text: 'التشكيلة'),
                Tab(text: 'الإحصائيات'),
                Tab(text: 'التعليق'),
                Tab(text: 'الترتيب'),
                Tab(text: 'الفورمة'),
              ],
            ),
          ),
          body: Column(children: [
            header(),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: green))
                  : TabBarView(children: [overview(), lineups(), stats(), commentary(), table(), form()]),
            ),
          ]),
        ),
      );

  Widget header() {
    final pre = m.state == 'pre';
    return Container(
      color: panel,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Row(children: [
        Expanded(child: bigTeam(m.home)),
        SizedBox(
          width: 120,
          child: pre
              ? Text(hm(m.date), textAlign: TextAlign.center, style: const TextStyle(color: green, fontSize: 28, fontWeight: FontWeight.w900))
              : Column(children: [
                  Text('${scoreOf('home')} - ${scoreOf('away')}',
                      textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: m.isLive ? red : line, borderRadius: BorderRadius.circular(8)),
                    child: Text(m.statusText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
        ),
        Expanded(child: bigTeam(m.away)),
      ]),
    );
  }

  Widget bigTeam(dynamic t) => Column(children: [
        logo('${t['team']['logo'] ?? ''}', 54),
        const SizedBox(height: 6),
        Text('${t['team']['displayName'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  Widget sectionTitle(String t) =>
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)));

  // ----- المباراة: الأحداث + معلومات -----
  Widget overview() {
    final kes = (summary?['keyEvents'] as List?) ?? [];
    final children = <Widget>[];
    if (kes.isNotEmpty) {
      children.add(card(child: Column(children: [sectionTitle('مجريات المباراة'), for (final e in kes) keyEventRow(e), const SizedBox(height: 8)])));
    } else {
      final det = (m.c['details'] as List?) ?? [];
      if (det.isNotEmpty) {
        children.add(card(child: Column(children: [sectionTitle('مجريات المباراة'), for (final e in det) keyEventRow(e), const SizedBox(height: 8)])));
      }
    }
    children.add(infoCard());
    final leaders = (summary?['leaders'] as List?) ?? [];
    if (leaders.isNotEmpty) children.add(leadersCard(leaders));
    return ListView(padding: const EdgeInsets.all(10), children: children);
  }

  Widget keyEventRow(dynamic e) {
    final typeText = '${e['type']?['text'] ?? ''}';
    final team = e['team'];
    final parts = ((e['participants'] as List?) ?? (e['athletesInvolved'] as List?) ?? [])
        .map((x) => '${x['athlete']?['displayName'] ?? x['displayName'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    final clock = '${e['clock']?['displayValue'] ?? ''}';
    if (team == null || team is! Map) {
      // حدث عام مثل بداية/نهاية الشوط
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(children: [
          const Expanded(child: Divider(color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(eventNames[typeText] ?? typeText, style: const TextStyle(color: mute, fontSize: 12)),
          ),
          const Expanded(child: Divider(color: line)),
        ]),
      );
    }
    final lower = typeText.toLowerCase();
    String icon;
    String text;
    if (e['scoringPlay'] == true) {
      icon = e['ownGoal'] == true || lower.contains('own') ? '⚽ ذاتي' : (e['penaltyKick'] == true || lower.contains('penalty')) ? '⚽ جزاء' : '⚽';
      text = parts.isEmpty ? 'هدف' : parts.first;
      if (parts.length > 1) text += '\nصناعة: ${parts[1]}';
    } else if (lower.contains('substitution') || e['substitution'] == true) {
      icon = '🔄';
      text = parts.length >= 2 ? '⬆ ${parts[0]}\n⬇ ${parts[1]}' : (parts.isEmpty ? 'تبديل' : parts.first);
    } else if (lower.contains('red') || e['redCard'] == true) {
      icon = '🟥';
      text = parts.isEmpty ? 'بطاقة حمراء' : parts.first;
    } else if (lower.contains('yellow') || e['yellowCard'] == true) {
      icon = '🟨';
      text = parts.isEmpty ? 'بطاقة صفراء' : parts.first;
    } else {
      icon = '•';
      text = parts.isEmpty ? typeText : parts.join('، ');
    }
    final isHome = '${team['id']}' == homeId;
    final content = Text('$icon $text', textAlign: isHome ? TextAlign.start : TextAlign.end, style: const TextStyle(fontSize: 13));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: isHome ? content : const SizedBox()),
        Container(
          width: 46,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(8)),
          child: Text(clock, textAlign: TextAlign.center, style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
        ),
        Expanded(child: isHome ? const SizedBox() : content),
      ]),
    );
  }

  Widget infoCard() {
    final gi = summary?['gameInfo'];
    final venue = gi?['venue']?['fullName'] ?? m.c['venue']?['fullName'];
    final city = gi?['venue']?['address']?['city'];
    final att = gi?['attendance'];
    final refs = (gi?['officials'] as List?) ?? [];
    final ref = refs.isNotEmpty ? (refs.first['displayName'] ?? refs.first['fullName']) : null;
    Widget row(IconData i, String label, String v) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(i, size: 18, color: green),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: mute)),
            const Spacer(),
            Flexible(child: Text(v, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
          ]),
        );
    return card(
      child: Column(children: [
        sectionTitle('معلومات المباراة'),
        row(Icons.event, 'الموعد', '${weekdays[m.date.weekday - 1]} ${dm(m.date)} · ${hm(m.date)}'),
        if (venue != null) row(Icons.stadium, 'الملعب', '$venue${city != null ? '، $city' : ''}'),
        if (ref != null) row(Icons.sports, 'الحكم', '$ref'),
        if (att != null && '$att' != '0') row(Icons.groups, 'الحضور', '$att'),
        row(Icons.emoji_events, 'البطولة', m.leagueName),
        const SizedBox(height: 6),
      ]),
    );
  }

  Widget leadersCard(List leaders) {
    final rows = <Widget>[];
    for (final t in leaders) {
      for (final cat in ((t['leaders'] as List?) ?? []).take(2)) {
        final ls = (cat['leaders'] as List?) ?? [];
        if (ls.isEmpty) continue;
        final l = ls.first;
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            logo('${t['team']?['logo'] ?? ''}', 20),
            const SizedBox(width: 8),
            Expanded(child: Text('${l['athlete']?['displayName'] ?? ''}', overflow: TextOverflow.ellipsis)),
            Text('${cat['displayName'] ?? ''}: ${l['displayValue'] ?? ''}', style: const TextStyle(color: mute, fontSize: 12)),
          ]),
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox();
    return card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sectionTitle('أبرز اللاعبين'), ...rows, const SizedBox(height: 6)]));
  }

  // ----- التشكيلة على الملعب -----
  List get rosters {
    final r = ((summary?['rosters'] as List?) ?? []).where((x) => ((x['roster'] as List?) ?? []).isNotEmpty).toList();
    r.sort((x, y) => (x['homeAway'] == 'home' ? 0 : 1) - (y['homeAway'] == 'home' ? 0 : 1));
    return r;
  }

  List<List<dynamic>>? lines(dynamic r) {
    final list = (r['roster'] as List?) ?? [];
    final starters = list.where((p) => p['starter'] == true).toList()
      ..sort((x, y) => (int.tryParse('${x['formationPlace']}') ?? 99).compareTo(int.tryParse('${y['formationPlace']}') ?? 99));
    final f = '${r['formation'] ?? ''}'.split('-').map((s) => int.tryParse(s.trim()) ?? 0).where((n) => n > 0).toList();
    if (starters.length != 11 || f.isEmpty || f.fold<int>(0, (a, b) => a + b) != 10) return null;
    final out = <List<dynamic>>[
      [starters.first]
    ];
    var i = 1;
    for (final n in f) {
      out.add(starters.sublist(i, i + n));
      i += n;
    }
    return out;
  }

  Widget lineups() {
    final rs = rosters;
    if (rs.isEmpty) return ListView(children: [emptyMsg('التشكيلة تنزل عادةً قبل المباراة بساعة.')]);
    final home = rs.first;
    final away = rs.length > 1 ? rs[1] : null;
    final hl = lines(home);
    final al = away == null ? null : lines(away);
    return ListView(padding: const EdgeInsets.all(10), children: [
      if (hl != null && al != null) pitch(home, hl, away, al),
      for (final r in rs) benchCard(r, showStarters: hl == null || al == null),
    ]);
  }

  Widget pitch(dynamic home, List<List<dynamic>> hl, dynamic away, List<List<dynamic>> al) {
    Widget teamHalf(List<List<dynamic>> ls, bool isHome) {
      final rows = ls.map((ln) => Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final p in ln) playerDot(p, isHome)],
            ),
          ));
      // المضيف: الحارس تحت. الضيف: الحارس فوق
      return Expanded(child: Column(children: isHome ? rows.toList().reversed.toList() : rows.toList()));
    }

    Widget formationLabel(dynamic r, bool isHome) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Text('${r['team']?['displayName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${r['formation'] ?? ''}', textDirection: TextDirection.ltr, style: TextStyle(color: isHome ? green : red, fontWeight: FontWeight.w800)),
          ]),
        );

    return card(
      child: Column(children: [
        formationLabel(away, false),
        AspectRatio(
          aspectRatio: 0.62,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E6B3A), Color(0xFF175A30)]),
            ),
            child: CustomPaint(
              painter: PitchPainter(),
              child: Column(children: [teamHalf(al, false), teamHalf(hl, true)]),
            ),
          ),
        ),
        formationLabel(home, true),
      ]),
    );
  }

  Map<String, int> marks(dynamic p) {
    final plays = (p['plays'] as List?) ?? [];
    var g = 0, y = 0, r = 0;
    for (final pl in plays) {
      if (pl['scoringPlay'] == true && pl['didAssist'] != true && pl['ownGoal'] != true) g++;
      if (pl['yellowCard'] == true) y++;
      if (pl['redCard'] == true) r++;
    }
    return {'g': g, 'y': y, 'r': r};
  }

  Widget playerDot(dynamic p, bool isHome) {
    final mk = marks(p);
    final name = lastName('${p['athlete']?['displayName'] ?? ''}');
    return GestureDetector(
      onTap: () => showPlayer(p),
      child: SizedBox(
        width: 66,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isHome ? green : red,
                shape: BoxShape.circle,
                border: Border.all(color: white, width: 2),
              ),
              child: Text('${p['jersey'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
            if (mk['g']! > 0)
              Positioned(top: -6, left: -8, child: Text(mk['g']! > 1 ? '⚽${mk['g']}' : '⚽', style: const TextStyle(fontSize: 11))),
            if (mk['r']! > 0)
              const Positioned(top: -4, right: -6, child: Text('🟥', style: TextStyle(fontSize: 10)))
            else if (mk['y']! > 0)
              const Positioned(top: -4, right: -6, child: Text('🟨', style: TextStyle(fontSize: 10))),
            if (p['subbedOut'] == true)
              const Positioned(bottom: -4, right: -6, child: Icon(Icons.arrow_downward, size: 14, color: Color(0xFFFF6B6B))),
          ]),
          const SizedBox(height: 3),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget benchCard(dynamic r, {required bool showStarters}) {
    final list = (r['roster'] as List?) ?? [];
    final starters = list.where((p) => p['starter'] == true).toList()
      ..sort((x, y) => (int.tryParse('${x['formationPlace']}') ?? 99).compareTo(int.tryParse('${y['formationPlace']}') ?? 99));
    final subs = list.where((p) => p['starter'] != true).toList()..sort((x, y) => (x['subbedIn'] == true ? 0 : 1) - (y['subbedIn'] == true ? 0 : 1));
    final logos = r['team']?['logos'] as List?;
    final isHome = r['homeAway'] == 'home';
    return card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: isHome ? green : red,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            logo(logos != null && logos.isNotEmpty ? '${logos.first['href']}' : null, 22),
            const SizedBox(width: 8),
            Expanded(child: Text('${r['team']?['displayName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
            if (r['formation'] != null) Text('${r['formation']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
        if (showStarters) ...[
          const Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 4), child: Text('الأساسيين', style: TextStyle(color: mute))),
          for (final p in starters) playerRow(p),
        ],
        if (subs.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 4), child: Text('الاحتياط', style: TextStyle(color: mute))),
        for (final p in subs) playerRow(p),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget playerRow(dynamic p) {
    final pos = '${p['position']?['abbreviation'] ?? ''}';
    final mk = marks(p);
    return InkWell(
      onTap: () => showPlayer(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          if (mk['g']! > 0) Text(' ⚽' * mk['g']!),
          if (mk['y']! > 0) const Text(' 🟨'),
          if (mk['r']! > 0) const Text(' 🟥'),
          if (p['subbedIn'] == true) const Icon(Icons.arrow_upward, size: 16, color: green),
          if (p['subbedOut'] == true) const Icon(Icons.arrow_downward, size: 16, color: red),
          const SizedBox(width: 6),
          Text(posNames[pos.isEmpty ? '' : pos[0]] ?? pos, style: const TextStyle(color: mute, fontSize: 12)),
        ]),
      ),
    );
  }

  void showPlayer(dynamic p) {
    final st = (p['stats'] as List?) ?? [];
    final rows = <Widget>[];
    for (final s in st) {
      final name = '${s['name']}';
      final label = playerStatNames[name];
      if (label == null) continue;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Text(label, style: const TextStyle(color: mute)),
          const Spacer(),
          Text('${s['displayValue'] ?? s['value'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ));
    }
    final pos = '${p['position']?['displayName'] ?? p['position']?['abbreviation'] ?? ''}';
    final posAr = posNames['${p['position']?['abbreviation'] ?? ''}'.isEmpty ? '' : '${p['position']?['abbreviation']}'[0]] ?? pos;
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .75),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(18), children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
                child: Text('${p['jersey'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['athlete']?['displayName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text(posAr, style: const TextStyle(color: mute)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            const Divider(color: line),
            if (rows.isEmpty) emptyMsg('ماكو إحصائيات لهذا اللاعب بهذي المباراة.') else ...rows,
          ]),
        ),
      ),
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
      Row(children: [logo('${m.home['team']['logo'] ?? ''}', 24), const Spacer(), logo('${m.away['team']['logo'] ?? ''}', 24)]),
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

  // ----- التعليق -----
  Widget commentary() {
    final cs = ((summary?['commentary'] as List?) ?? []).toList();
    if (cs.isEmpty) return ListView(children: [emptyMsg('التعليق غير متوفر لهذي المباراة.')]);
    final items = cs.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('التعليق من المصدر باللغة الإنجليزية · الأحدث فوق', style: TextStyle(color: mute, fontSize: 12)),
          );
        }
        final c = items[i - 1];
        final type = '${c['play']?['type']?['type'] ?? ''}';
        final isGoal = type.contains('goal') || c['play']?['scoringPlay'] == true;
        final icon = isGoal
            ? '⚽'
            : type.contains('yellow')
                ? '🟨'
                : type.contains('red')
                    ? '🟥'
                    : type.contains('substitution')
                        ? '🔄'
                        : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isGoal ? green.withValues(alpha: .18) : panel,
            borderRadius: BorderRadius.circular(10),
            border: Border(right: BorderSide(color: isGoal ? green : line, width: 3)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 44,
              child: Text('${c['time']?['displayValue'] ?? ''}', style: const TextStyle(color: green, fontWeight: FontWeight.w800)),
            ),
            if (icon.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 6), child: Text(icon)),
            Expanded(
              child: Text('${c['text'] ?? ''}', textDirection: TextDirection.ltr, textAlign: TextAlign.left, style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ]),
        );
      },
    );
  }

  // ----- الترتيب داخل المباراة -----
  Widget table() {
    final groups = (summary?['standings']?['groups'] as List?) ?? [];
    final ids = {homeId, '${m.away['team']['id']}'};
    final out = <Widget>[];
    for (final g in groups) {
      final ents = ((g['standings']?['entries'] as List?) ?? []).toList();
      if (ents.isEmpty) continue;
      String st(dynamic en, String k) {
        for (final s in (en['stats'] as List? ?? [])) {
          if (s['name'] == k) return '${s['displayValue'] ?? ''}';
        }
        return '';
      }

      ents.sort((a, b) => (int.tryParse(st(a, 'rank')) ?? 0).compareTo(int.tryParse(st(b, 'rank')) ?? 0));
      const h = TextStyle(color: mute, fontSize: 12);
      Widget cell(String t, {TextStyle? s, double w = 30}) => SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: s ?? const TextStyle(fontSize: 13)));
      out.add(card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            if ('${g['header'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.all(6), child: Text('${g['header']}', style: const TextStyle(fontWeight: FontWeight.w800))),
            Row(children: [
              cell('#', s: h, w: 26),
              const Expanded(child: Text('الفريق', style: h)),
              cell('لعب', s: h),
              cell('+/-', s: h, w: 36),
              cell('نقاط', s: h, w: 36),
            ]),
            const Divider(color: line),
            for (var i = 0; i < ents.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                decoration: BoxDecoration(
                  color: ids.contains('${ents[i]['team']?['id'] ?? ents[i]['id']}') ? green.withValues(alpha: .2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  cell(st(ents[i], 'rank').isEmpty ? '${i + 1}' : st(ents[i], 'rank'), w: 26),
                  Expanded(
                    child: Row(children: [
                      logo(((ents[i]['logo'] as List?)?.isNotEmpty ?? false) ? '${ents[i]['logo'][0]['href']}' : null, 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${ents[i]['team'] is Map ? (ents[i]['team']['shortDisplayName'] ?? ents[i]['team']['displayName'] ?? '') : ents[i]['team'] ?? ''}',
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      ),
                    ]),
                  ),
                  cell(st(ents[i], 'gamesPlayed')),
                  SizedBox(width: 36, child: Text(st(ents[i], 'pointDifferential'), textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13))),
                  cell(st(ents[i], 'points'), w: 36, s: const TextStyle(color: green, fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ));
    }
    if (out.isEmpty) {
      return ListView(children: [
        emptyMsg('الترتيب غير متوفر هنا.'),
        Center(
          child: OutlinedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StandingsPage(id: m.leagueId, name: m.leagueName))),
            child: const Text('افتح ترتيب البطولة'),
          ),
        ),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(10), children: out);
  }

  // ----- الفورمة والمواجهات -----
  Widget form() {
    final last = (summary?['lastFiveGames'] as List?) ?? [];
    final h2h = (summary?['headToHeadGames'] as List?) ?? [];
    final widgets = <Widget>[];
    final sorted = last.toList()..sort((x, y) => ('${x['team']?['id']}' == homeId ? 0 : 1) - ('${y['team']?['id']}' == homeId ? 0 : 1));
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
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [for (final e in evs) resultChip('${e['gameResult'] ?? ''}')])),
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
        Expanded(child: Text(h2h ? '${e['competitionName'] ?? e['leagueName'] ?? ''}' : '$at $opp', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        Text('${e['score'] ?? ''}', textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, color: r == 'W' ? green : r == 'L' ? red : white)),
      ]),
    );
  }
}

// رسم خطوط الملعب
class PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = s.width, h = s.height;
    canvas.drawRect(Rect.fromLTWH(6, 6, w - 12, h - 12), p);
    canvas.drawLine(Offset(6, h / 2), Offset(w - 6, h / 2), p);
    canvas.drawCircle(Offset(w / 2, h / 2), w * .13, p);
    final bw = w * .56, bh = h * .13;
    canvas.drawRect(Rect.fromLTWH((w - bw) / 2, 6, bw, bh), p);
    canvas.drawRect(Rect.fromLTWH((w - bw) / 2, h - 6 - bh, bw, bh), p);
    final sw = w * .26, sh = h * .05;
    canvas.drawRect(Rect.fromLTWH((w - sw) / 2, 6, sw, sh), p);
    canvas.drawRect(Rect.fromLTWH((w - sw) / 2, h - 6 - sh, sw, sh), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
