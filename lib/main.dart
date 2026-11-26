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
                border: Border
