import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class OrmaNotifications {
  OrmaNotifications._();
  static final OrmaNotifications instance = OrmaNotifications._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  bool ready = false;

  Future<void> initialize() async {
    if (ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    ready = true;
  }

  Future<void> requestPermission() async {
    await initialize();
    await plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int _stableId(String value, int suffix) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return ((hash * 10) + suffix) & 0x7fffffff;
  }

  Future<void> scheduleFor(Reminder reminder, {required bool malayalam}) async {
    await initialize();
    final base = reminder.id;
    for (var i = 0; i < 4; i++) {
      await plugin.cancel(id: _stableId(base, i));
    }
    if (reminder.paid || reminder.isComplete) return;

    final due = DateTime(
      reminder.dueDate.year, reminder.dueDate.month, reminder.dueDate.day);
    final items = <({int daysBefore, int hour, int minute, int suffix, String ml, String en})>[
      (daysBefore: 7, hour: 9, minute: 0, suffix: 0,
       ml: '7 ദിവസത്തിനകം ${reminder.title} അടയ്ക്കണം',
       en: '${reminder.title} payment is due in 7 days'),
      (daysBefore: 1, hour: 9, minute: 0, suffix: 1,
       ml: 'നാളെ ${reminder.title} അടയ്ക്കേണ്ടതാണ്',
       en: '${reminder.title} payment is due tomorrow'),
      (daysBefore: 0, hour: 8, minute: 0, suffix: 2,
       ml: 'ഇന്ന് ${reminder.title} അടയ്ക്കേണ്ട ദിവസമാണ്',
       en: '${reminder.title} payment is due today'),
      (daysBefore: -1, hour: 9, minute: 0, suffix: 3,
       ml: '${reminder.title} അടവ് കുടിശ്ശികയാണ്',
       en: '${reminder.title} payment is overdue'),
    ];

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'orma_payment_reminders',
        'ORMA Payment Reminders',
        channelDescription: 'EMI, loan, chitty and bill due-date reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    for (final item in items) {
      final date = due.subtract(Duration(days: item.daysBefore));
      final scheduled = tz.TZDateTime(
        tz.local, date.year, date.month, date.day, item.hour, item.minute);
      if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) continue;
      await plugin.zonedSchedule(
        id: _stableId(base, item.suffix),
        title: malayalam ? 'ORMA – ഓർമ്മപ്പെടുത്തൽ' : 'ORMA – Reminder',
        body: malayalam ? item.ml : item.en,
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.id,
      );
    }
  }

  Future<void> rescheduleAll(List<Reminder> reminders,
      {required bool malayalam}) async {
    await initialize();
    await plugin.cancelAll();
    for (final reminder in reminders) {
      await scheduleFor(reminder, malayalam: malayalam);
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrmaApp());
}

class OrmaApp extends StatelessWidget {
  const OrmaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ORMA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A5A44)),
          scaffoldBackgroundColor: const Color(0xFFFFFAF6),
        ),
        home: const DashboardScreen(),
      );
}

class Reminder {
  String id, title, category, frequency, monthlyMode, weekday, monthlyWeek;
  double amount, currentInstallmentPaid, totalPaidAmount;
  DateTime dueDate, startDate;
  DateTime? endDate;
  int? totalInstallments;
  int paidInstallments;
  bool paid;
  String notes;
  List<String> paymentHistory;

  Reminder({
    required this.id, required this.title, required this.category,
    required this.amount, required this.dueDate, required this.startDate,
    this.endDate, this.totalInstallments, this.paidInstallments = 0,
    this.frequency = 'One Time', this.monthlyMode = 'Date',
    this.weekday = 'Monday', this.monthlyWeek = 'First',
    this.paid = false, this.notes = '',
    this.currentInstallmentPaid = 0, this.totalPaidAmount = 0,
    List<String>? paymentHistory,
  }) : paymentHistory = paymentHistory ?? [];

  int get calculatedInstallments {
    if (frequency == 'One Time') return 1;
    if (endDate == null) return totalInstallments ?? 0;
    var count = 0;
    var cursor = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate!.year, endDate!.month, endDate!.day);
    while (!cursor.isAfter(end) && count < 5000) {
      count++;
      final next = nextScheduledDate(
          cursor, frequency, monthlyMode, weekday, monthlyWeek);
      if (!next.isAfter(cursor)) break;
      cursor = next;
    }
    return count;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'category': category, 'amount': amount,
    'dueDate': dueDate.toIso8601String(),
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'totalInstallments': calculatedInstallments,
    'paidInstallments': paidInstallments,
    'frequency': frequency, 'monthlyMode': monthlyMode,
    'weekday': weekday, 'monthlyWeek': monthlyWeek,
    'paid': paid, 'notes': notes, 'paymentHistory': paymentHistory,
    'currentInstallmentPaid': currentInstallmentPaid,
    'totalPaidAmount': totalPaidAmount,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
    title: j['title'] ?? '', category: j['category'] ?? 'Other',
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    dueDate: DateTime.tryParse(j['dueDate'] ?? '') ?? DateTime.now(),
    startDate: DateTime.tryParse(j['startDate'] ?? j['dueDate'] ?? '') ??
        DateTime.now(),
    endDate: j['endDate'] == null ? null : DateTime.tryParse(j['endDate']),
    totalInstallments: j['totalInstallments'] as int?,
    paidInstallments: j['paidInstallments'] as int? ?? 0,
    frequency: j['frequency'] ?? 'One Time',
    monthlyMode: j['monthlyMode'] ?? 'Date',
    weekday: j['weekday'] ?? 'Monday',
    monthlyWeek: j['monthlyWeek'] ?? 'First',
    paid: j['paid'] as bool? ?? false, notes: j['notes'] ?? '',
    paymentHistory: (j['paymentHistory'] as List?)
        ?.map((e) => e.toString()).toList() ?? [],
    currentInstallmentPaid:
        (j['currentInstallmentPaid'] as num?)?.toDouble() ?? 0,
    totalPaidAmount: (j['totalPaidAmount'] as num?)?.toDouble() ??
        ((j['paidInstallments'] as int? ?? 0) *
            ((j['amount'] as num?)?.toDouble() ?? 0)),
  );

  bool get isComplete =>
      (calculatedInstallments > 0 &&
          paidInstallments >= calculatedInstallments) ||
      (endDate != null && dueDate.isAfter(endDate!));
}

int _weekdayNumber(String day) => const {
  'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
  'Friday': 5, 'Saturday': 6, 'Sunday': 7,
}[day] ?? 1;

DateTime nextScheduledDate(DateTime from, String frequency,
    String monthlyMode, String weekday, String monthlyWeek) {
  switch (frequency) {
    case 'Daily':
      return from.add(const Duration(days: 1));
    case 'Weekly':
      return from.add(const Duration(days: 7));
    case 'Monthly':
      if (monthlyMode == 'Weekday') {
        final first = DateTime(from.year, from.month + 1, 1);
        final wd = _weekdayNumber(weekday);
        final offset = (wd - first.weekday + 7) % 7;
        final ordinal = {'First': 0, 'Second': 1, 'Third': 2,
          'Fourth': 3, 'Last': -1}[monthlyWeek] ?? 0;
        if (ordinal == -1) {
          final last = DateTime(first.year, first.month + 1, 0);
          return last.subtract(Duration(days: (last.weekday - wd + 7) % 7));
        }
        return DateTime(first.year, first.month, 1 + offset + ordinal * 7);
      }
      final nextMonth = DateTime(from.year, from.month + 1, 1);
      final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      return DateTime(nextMonth.year, nextMonth.month,
          from.day > lastDay ? lastDay : from.day);
    case 'Yearly':
      final nextYear = DateTime(from.year + 1, from.month, 1);
      final lastDay = DateTime(nextYear.year, nextYear.month + 1, 0).day;
      return DateTime(nextYear.year, nextYear.month,
          from.day > lastDay ? lastDay : from.day);
    default:
      return from;
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const storageKey = 'orma_reminders_v2';
  List<Reminder> reminders = [];
  bool loading = true, malayalam = true;
  String assistantName = 'കാർത്തിക';

  String tr(String ml, String en) => malayalam ? ml : en;
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool overdue(Reminder r) =>
      !r.paid && dateOnly(r.dueDate).isBefore(dateOnly(DateTime.now()));

  @override
  void initState() {
    super.initState();
    load();
    OrmaNotifications.instance.initialize();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(storageKey) ?? p.getString('orma_reminders_v1');
    if (raw != null) {
      try {
        reminders = (jsonDecode(raw) as List)
            .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
    await OrmaNotifications.instance.rescheduleAll(reminders, malayalam: malayalam);
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(storageKey,
        jsonEncode(reminders.map((e) => e.toJson()).toList()));
  }

  double get monthDue {
    final n = DateTime.now();
    return reminders.where((r) =>
      !r.paid && r.dueDate.year == n.year && r.dueDate.month == n.month)
      .fold(0, (s, r) => s + r.amount);
  }

  Future<void> addOrEdit({Reminder? reminder}) async {
    final result = await Navigator.push<Reminder>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderForm(
          malayalam: malayalam,
          reminder: reminder,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      final i = reminders.indexWhere((r) => r.id == result.id);
      if (i < 0) {
        reminders.add(result);
      } else {
        reminders[i] = result;
      }
    });
    await save();
    await OrmaNotifications.instance.rescheduleAll(reminders, malayalam: malayalam);
  }

  DateTime nextDue(Reminder r) {
    final d = r.dueDate;
    switch (r.frequency) {
      case 'Daily':
        return d.add(const Duration(days: 1));
      case 'Weekly':
        return d.add(const Duration(days: 7));
      case 'Monthly':
        if (r.monthlyMode == 'Weekday') {
          final weekday = _weekdayNumber(r.weekday);
          return _nthWeekdayOfNextMonth(d, weekday, r.monthlyWeek);
        }
        final nextMonth = DateTime(d.year, d.month + 1, 1);
        final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
        return DateTime(nextMonth.year, nextMonth.month,
            d.day > lastDay ? lastDay : d.day);
      case 'Yearly':
        final y = DateTime(d.year + 1, d.month, 1);
        final lastDay = DateTime(y.year, y.month + 1, 0).day;
        return DateTime(y.year, y.month, d.day > lastDay ? lastDay : d.day);
      default:
        return d;
    }
  }

  int _weekdayNumber(String day) => const {
        'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
        'Friday': 5, 'Saturday': 6, 'Sunday': 7,
      }[day] ?? 1;

  DateTime _nthWeekdayOfNextMonth(DateTime from, int weekday, String which) {
    final first = DateTime(from.year, from.month + 1, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    int day = 1 + offset;
    final ordinal = {'First': 0, 'Second': 1, 'Third': 2, 'Fourth': 3,
          'Last': -1}[which] ?? 0;
    if (ordinal == -1) {
      final last = DateTime(first.year, first.month + 1, 0);
      return last.subtract(Duration(days: (last.weekday - weekday + 7) % 7));
    }
    day += ordinal * 7;
    return DateTime(first.year, first.month, day);
  }

  Future<void> markPaid(Reminder r) async {
    final controller = TextEditingController(text: r.amount.toStringAsFixed(2));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('അടച്ച തുക രേഖപ്പെടുത്തുക', 'Record payment')),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('ഇപ്പോൾ അടച്ച തുക (₹)', 'Amount paid now (₹)')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text(tr('റദ്ദാക്കുക', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(controller.text.trim());
              if (amount != null && amount > 0) Navigator.pop(context, amount);
            },
            child: Text(tr('സേവ്', 'Save'))),
        ],
      ),
    );
    if (value == null) return;
    setState(() {
      r.totalPaidAmount += value;
      r.currentInstallmentPaid += value;
      r.paymentHistory.add(
        '${DateTime.now().toIso8601String()} | ₹${value.toStringAsFixed(2)}');
      while (r.currentInstallmentPaid >= r.amount &&
          r.paidInstallments < r.calculatedInstallments) {
        r.currentInstallmentPaid -= r.amount;
        r.paidInstallments++;
        if (r.frequency == 'One Time') {
          r.paid = true;
          break;
        }
        r.dueDate = nextScheduledDate(
          r.dueDate, r.frequency, r.monthlyMode, r.weekday, r.monthlyWeek);
      }
      if (r.paidInstallments >= r.calculatedInstallments ||
          (r.endDate != null && r.dueDate.isAfter(r.endDate!))) {
        r.paid = true;
      }
    });
    await save();
    await OrmaNotifications.instance.rescheduleAll(reminders, malayalam: malayalam);
  }

  Future<void> delete(Reminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('നീക്കം ചെയ്യണോ?', 'Delete reminder?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(tr('വേണ്ട', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: Text(tr('നീക്കം ചെയ്യുക', 'Delete'))),
        ],
      ),
    );
    if (ok == true) {
      setState(() => reminders.removeWhere((e) => e.id == r.id));
      await save();
      await OrmaNotifications.instance.rescheduleAll(reminders, malayalam: malayalam);
    }
  }

  Future<void> settings() async {
    final c = TextEditingController(text: assistantName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('അസിസ്റ്റന്റിന്റെ പേര്', 'Assistant name')),
        content: TextField(controller: c),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text(tr('റദ്ദാക്കുക', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()),
              child: Text(tr('സേവ്', 'Save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) setState(() => assistantName = name);
  }

  @override
  Widget build(BuildContext context) {
    final active = reminders.where((r) => !r.paid).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final lateCount = active.where(overdue).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ഓർമ്മ  ORMA',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => setState(() => malayalam = !malayalam),
            child: Text(malayalam ? 'EN' : 'മലയാളം')),
          IconButton(
            tooltip: tr('അറിയിപ്പുകൾ അനുവദിക്കുക', 'Enable notifications'),
            onPressed: () async {
              await OrmaNotifications.instance.requestPermission();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr('അറിയിപ്പ് അനുമതി അഭ്യർത്ഥിച്ചു', 'Notification permission requested'))));
            },
            icon: const Icon(Icons.notifications_active_outlined)),
          IconButton(onPressed: settings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addOrEdit(),
        icon: const Icon(Icons.add),
        label: Text(tr('റിമൈൻഡർ ചേർക്കുക', 'Add reminder')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Card(
                  elevation: 0,
                  color: const Color(0xFFF1E5DA),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset('assets/karthika.jpg',
                          width: 82, height: 96, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 82, height: 96,
                            child: Icon(Icons.person, size: 42))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('നമസ്കാരം! ഞാൻ $assistantName',
                              'Hello! I am $assistantName'),
                              style: const TextStyle(fontWeight: FontWeight.bold,
                                  fontSize: 17)),
                          const SizedBox(height: 5),
                          Text(tr('നിങ്ങളുടെ പ്രധാനപ്പെട്ട കാര്യങ്ങൾ ഇനി മറക്കേണ്ട.',
                              'Let me help you remember what matters.')),
                        ],
                      )),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _quickAccess(
                    tr('കലണ്ടർ', 'Calendar'), Icons.calendar_month_rounded,
                    const Color(0xFFEAF2FF), const Color(0xFF3269B5),
                    () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => OrmaCalendarScreen(
                        reminders: List<Reminder>.from(reminders),
                        malayalam: malayalam))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _quickAccess(
                    tr('Personal Reminder', 'Personal Reminder'), Icons.notifications_active_rounded,
                    const Color(0xFFFFF0E8), const Color(0xFFC66A38),
                    () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PersonalReminderScreen(malayalam: malayalam))),
                  )),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _summary(tr('ഈ മാസത്തെ അടവ്', 'Due this month'),
                      '₹${monthDue.toStringAsFixed(2)}', Icons.wallet_outlined)),
                  const SizedBox(width: 10),
                  Expanded(child: _summary(tr('കുടിശ്ശിക', 'Overdue'),
                      '$lateCount', Icons.warning_amber_rounded)),
                ]),
                const SizedBox(height: 20),
                Text(tr('അടുത്ത അടവുകൾ', 'Upcoming payments'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (active.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('ഇപ്പോൾ അടവുകൾ ഒന്നുമില്ല',
                        'No upcoming payments yet'))))
                else
                  ...active.map(_reminderTile),
                const SizedBox(height: 18),
                Text(tr('അടച്ചവ', 'Paid reminders'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                ...reminders.where((r) => r.paid).map(_reminderTile),
              ],
            ),
    );
  }

  Widget _quickAccess(String title, IconData icon, Color bg, Color fg,
      VoidCallback onTap) => Card(
    elevation: 0,
    color: bg,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        child: Column(children: [
          Icon(icon, color: fg, size: 32),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ]),
      ),
    ),
  );

  Widget _summary(String title, String value, IconData icon) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget _reminderTile(Reminder r) {
    final late = overdue(r);
    final status = r.paid ? tr('അടച്ചു', 'PAID')
        : late ? tr('കുടിശ്ശിക', 'OVERDUE') : tr('അടയ്ക്കാനുണ്ട്', 'PENDING');
    final color = r.paid ? Colors.green : late ? Colors.red : Colors.orange.shade800;
    final total = '${r.calculatedInstallments}';
    final remainingCount = (r.calculatedInstallments - r.paidInstallments).clamp(0, 999999);
    final balanceAmount = (r.calculatedInstallments * r.amount - r.totalPaidAmount).clamp(0, double.infinity);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.12),
          child: Icon(r.paid ? Icons.check : Icons.event_note, color: color)),
        title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${r.category} • ${r.dueDate.day}/${r.dueDate.month}/${r.dueDate.year}\n'
          '₹${r.amount.toStringAsFixed(2)} • ${r.frequency} • $status\n'
          '${tr('ആകെ അടവുകൾ', 'Total')}: $total • ${tr('അടച്ചത്', 'Paid')}: ${r.paidInstallments}\n'
          '${tr('ബാക്കി', 'Balance')}: $remainingCount • ₹${balanceAmount.toStringAsFixed(2)}',
          style: TextStyle(color: color, height: 1.4)),
        isThreeLine: true,
        onTap: () => addOrEdit(reminder: r),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'paid') markPaid(r);
            if (v == 'edit') addOrEdit(reminder: r);
            if (v == 'delete') delete(r);
            if (v == 'history') showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(tr('Payment History', 'Payment History')),
                content: SizedBox(
                  width: double.maxFinite,
                  child: r.paymentHistory.isEmpty
                    ? Text(tr('ഇതുവരെ പേയ്മെന്റ് ഇല്ല', 'No payments recorded'))
                    : ListView(shrinkWrap: true, children: r.paymentHistory
                      .map((d) => ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(DateTime.parse(d).toLocal().toString().split('.').first),
                      )).toList()),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text('OK'))],
              ));
          },
          itemBuilder: (_) => [
            if (!r.paid) PopupMenuItem(value: 'paid',
              child: Text(tr('അടച്ചതായി രേഖപ്പെടുത്തുക', 'Mark installment paid'))),
            PopupMenuItem(value: 'history',
              child: Text(tr('പേയ്മെന്റ് ചരിത്രം', 'Payment history'))),
            PopupMenuItem(value: 'edit', child: Text(tr('തിരുത്തുക', 'Edit'))),
            PopupMenuItem(value: 'delete', child: Text(tr('നീക്കം ചെയ്യുക', 'Delete'))),
          ],
        ),
      ),
    );
  }
}


class PersonalReminder {
  final String id;
  final String title;
  final String notes;
  final DateTime date;
  const PersonalReminder({required this.id, required this.title,
    required this.notes, required this.date});
  Map<String, dynamic> toJson() => {'id': id, 'title': title,
    'notes': notes, 'date': date.toIso8601String()};
  factory PersonalReminder.fromJson(Map<String, dynamic> j) => PersonalReminder(
    id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
    title: j['title']?.toString() ?? '', notes: j['notes']?.toString() ?? '',
    date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now());
}

class PersonalReminderScreen extends StatefulWidget {
  final bool malayalam;
  const PersonalReminderScreen({super.key, required this.malayalam});
  @override
  State<PersonalReminderScreen> createState() => _PersonalReminderScreenState();
}

class _PersonalReminderScreenState extends State<PersonalReminderScreen> {
  static const key = 'orma_personal_reminders_v1';
  List<PersonalReminder> items = [];
  bool loading = true;
  bool get ml => widget.malayalam;
  String tr(String a, String b) => ml ? a : b;

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null) {
      try { items = (jsonDecode(raw) as List).map((e) =>
        PersonalReminder.fromJson(Map<String, dynamic>.from(e))).toList(); }
      catch (_) { items = []; }
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
  Future<void> editItem({PersonalReminder? old}) async {
    final title = TextEditingController(text: old?.title ?? '');
    final notes = TextEditingController(text: old?.notes ?? '');
    DateTime date = old?.date ?? DateTime.now();
    final result = await showDialog<PersonalReminder>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text(old == null ? tr('പുതിയ ഓർമ്മപ്പെടുത്തൽ', 'New personal reminder') : tr('തിരുത്തുക', 'Edit reminder')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: InputDecoration(labelText: tr('എന്താണ് ഓർക്കേണ്ടത്?', 'What should I remember?'))),
          const SizedBox(height: 10),
          TextField(controller: notes, maxLines: 2, decoration: InputDecoration(labelText: tr('കുറിപ്പുകൾ (ഐച്ഛികം)', 'Notes (optional)'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () async {
            final d = await showDatePicker(context: ctx, initialDate: date,
              firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (d != null) setDialog(() => date = d);
          }, icon: const Icon(Icons.calendar_today),
            label: Text('${date.day}/${date.month}/${date.year}')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('റദ്ദാക്കുക', 'Cancel'))),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(ctx, PersonalReminder(id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
              title: title.text.trim(), notes: notes.text.trim(), date: date));
          }, child: Text(tr('സേവ്', 'Save'))),
        ],
      )));
    title.dispose(); notes.dispose();
    if (result == null) return;
    setState(() {
      final i = items.indexWhere((e) => e.id == result.id);
      if (i < 0) items.add(result); else items[i] = result;
      items.sort((a,b) => a.date.compareTo(b.date));
    });
    await persist();
  }
  Future<void> remove(PersonalReminder item) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr('നീക്കം ചെയ്യണോ?', 'Delete reminder?')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('വേണ്ട', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('നീക്കം ചെയ്യുക', 'Delete')))]));
    if (ok == true) { setState(() => items.removeWhere((e) => e.id == item.id)); await persist(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Personal Reminder', 'Personal Reminder'))),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => editItem(),
      icon: const Icon(Icons.add), label: Text(tr('ചേർക്കുക', 'Add reminder'))),
    body: loading ? const Center(child: CircularProgressIndicator()) : items.isEmpty
      ? Center(child: Text(tr('ഇതുവരെ ഓർമ്മപ്പെടുത്തലുകളില്ല', 'No personal reminders yet')))
      : ListView(padding: const EdgeInsets.all(16), children: items.map((e) => Card(
        child: ListTile(leading: const Icon(Icons.notifications_active_outlined),
          title: Text(e.title), subtitle: Text('${e.date.day}/${e.date.month}/${e.date.year}${e.notes.isEmpty ? '' : '\n${e.notes}'}'),
          onTap: () => editItem(old: e), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => remove(e))))).toList()),
  );
}

class OrmaCalendarScreen extends StatefulWidget {
  final List<Reminder> reminders;
  final bool malayalam;
  const OrmaCalendarScreen({super.key, required this.reminders, required this.malayalam});
  @override
  State<OrmaCalendarScreen> createState() => _OrmaCalendarScreenState();
}

class _OrmaCalendarScreenState extends State<OrmaCalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = DateTime.now();
  List<PersonalReminder> personal = [];
  bool get ml => widget.malayalam;
  String tr(String a, String b) => ml ? a : b;
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  @override
  void initState() { super.initState(); loadPersonal(); }
  Future<void> loadPersonal() async {
    final p = await SharedPreferences.getInstance(); final raw = p.getString('orma_personal_reminders_v1');
    if (raw != null) { try { personal = (jsonDecode(raw) as List).map((e) => PersonalReminder.fromJson(Map<String,dynamic>.from(e))).toList(); } catch (_) {} }
    if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final cells = List.generate(42, (i) => start.add(Duration(days: i)));
    final due = widget.reminders.where((r) => !r.paid && same(r.dueDate, selected)).toList();
    final own = personal.where((r) => same(r.date, selected)).toList();
    final weekdays = ml ? ['തിങ്കൾ','ചൊവ്വ','ബുധൻ','വ്യാഴം','വെള്ളി','ശനി','ഞായർ'] : ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return Scaffold(appBar: AppBar(title: Text(tr('കലണ്ടർ', 'Calendar'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(onPressed: () => setState(() { month = DateTime(month.year, month.month-1); }), icon: const Icon(Icons.chevron_left)),
          Text('${month.month}/${month.year}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(onPressed: () => setState(() { month = DateTime(month.year, month.month+1); }), icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: weekdays.map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))).toList()),
        const SizedBox(height: 8),
        GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: 42, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.15),
          itemBuilder: (ctx, i) {
            final d = cells[i]; final inMonth = d.month == month.month;
            final hasDue = widget.reminders.any((r) => !r.paid && same(r.dueDate,d)) || personal.any((r) => same(r.date,d));
            return InkWell(onTap: () => setState(() => selected = d), child: Container(
              margin: const EdgeInsets.all(2), decoration: BoxDecoration(
                color: same(d, selected) ? Theme.of(context).colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(10)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${d.day}', style: TextStyle(color: inMonth ? null : Colors.black26, fontWeight: same(d,selected) ? FontWeight.bold : FontWeight.normal)),
                if (hasDue) Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle)),
              ]),
            ));
          }),
        const Divider(height: 24),
        Text('${tr('തിരഞ്ഞെടുത്ത തീയതി', 'Selected date')}: ${selected.day}/${selected.month}/${selected.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (due.isEmpty && own.isEmpty) Text(tr('ഈ തീയതിയിൽ റിമൈൻഡറുകളില്ല', 'No reminders on this date')),
        ...due.map((r) => ListTile(leading: const Icon(Icons.payments_outlined), title: Text(r.title), subtitle: Text('${r.category} • ₹${r.amount.toStringAsFixed(2)}'))),
        ...own.map((r) => ListTile(leading: const Icon(Icons.notifications_active_outlined), title: Text(r.title), subtitle: Text(r.notes))),
      ]));
  }
}

class ReminderForm extends StatefulWidget {
  final bool malayalam;
  final Reminder? reminder;
  const ReminderForm({super.key, required this.malayalam, this.reminder});
  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final formKey = GlobalKey<FormState>();
  late TextEditingController title, amount, notes, previousCount, previousAmount;
  final List<DateTime> previousPaymentDates = [];
  late String category, frequency, monthlyMode, weekday, monthlyWeek;
  late DateTime startDate, dueDate;
  DateTime? endDate;
  bool paid = false;
  bool useEndDate = false;

  bool get ml => widget.malayalam;
  String tr(String a, String b) => ml ? a : b;
  final categories = ['EMI', 'Loan', 'Chitty', 'Electricity', 'Water',
    'Insurance', 'Rent', 'Other'];
  final frequencies = ['One Time', 'Daily', 'Weekly', 'Monthly', 'Yearly'];
  final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'];
  final ordinalDays = ['First', 'Second', 'Third', 'Fourth', 'Last'];

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    title = TextEditingController(text: r?.title ?? '');
    amount = TextEditingController(text: r == null ? '' : r.amount.toString());
    notes = TextEditingController(text: r?.notes ?? '');
    previousCount = TextEditingController(text: r == null ? '0' : '${r.paidInstallments}');
    previousAmount = TextEditingController(text: r == null ? '0' : r.totalPaidAmount.toStringAsFixed(2));
    if (r != null) {
      for (final entry in r.paymentHistory) {
        final dateText = entry.split('|').first.trim();
        final parsed = DateTime.tryParse(dateText);
        if (parsed != null) previousPaymentDates.add(parsed);
      }
    }
    category = r?.category ?? 'EMI';
    frequency = r?.frequency ?? 'Monthly';
    monthlyMode = r?.monthlyMode ?? 'Date';
    weekday = r?.weekday ?? 'Monday';
    monthlyWeek = r?.monthlyWeek ?? 'First';
    startDate = r?.startDate ?? DateTime.now();
    dueDate = r?.dueDate ?? DateTime.now();
    endDate = r?.endDate;
    useEndDate = endDate != null;
    paid = r?.paid ?? false;
  }

  @override
  void dispose() {
    title.dispose(); amount.dispose(); notes.dispose();
    previousCount.dispose(); previousAmount.dispose();
    super.dispose();
  }

  Future<void> pickDate({required bool start}) async {
    final initial = start ? startDate : (endDate ?? dueDate);
    final picked = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked == null) return;
    setState(() {
      if (start) {
        startDate = picked;
        dueDate = picked;
      } else {
        endDate = picked;
        useEndDate = true;
      }
    });
  }

  Future<void> addPreviousPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => previousPaymentDates.add(picked));
      previousPaymentDates.sort();
    }
  }

  void save() {
    if (!formKey.currentState!.validate()) return;
    final count = frequency == 'One Time' ? 1 : null;
    final oldCount = int.tryParse(previousCount.text.trim()) ?? 0;
    final oldAmount = double.tryParse(previousAmount.text.trim()) ?? 0;
    if (oldCount < 0 || oldAmount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('മുൻപ് അടച്ച എണ്ണം/തുക ശരിയായി നൽകുക',
            'Enter valid previous installment count and amount'))));
      return;
    }
    if (count != null && oldCount > count) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('മുൻപ് അടച്ച തവണകൾ ആകെ തവണകളെക്കാൾ കൂടുതലാകരുത്',
            'Previous paid installments cannot exceed total installments'))));
      return;
    }
    if (frequency != 'One Time' && (!useEndDate || endDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('ആവർത്തിക്കുന്ന അടവിന് അവസാന തീയതി നൽകുക',
            'Please set an end date for recurring payments'))));
      return;
    }
    if (useEndDate && endDate != null && endDate!.isBefore(startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('അവസാന തീയതി ആരംഭ തീയതിക്ക് ശേഷമായിരിക്കണം',
            'End date must be after start date'))));
      return;
    }
    final old = widget.reminder;
    final result = Reminder(
      id: old?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.text.trim(), category: category,
      amount: double.parse(amount.text.trim()),
      dueDate: dueDate, startDate: startDate,
      endDate: useEndDate ? endDate : null,
      totalInstallments: count,
      paidInstallments: old == null ? oldCount : old.paidInstallments,
      frequency: frequency, monthlyMode: monthlyMode,
      weekday: weekday, monthlyWeek: monthlyWeek,
      paid: paid, notes: notes.text.trim(),
      paymentHistory: old == null
          ? previousPaymentDates.map((d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} | Previous payment').toList()
          : old.paymentHistory,
      currentInstallmentPaid: old?.currentInstallmentPaid ?? 0,
      totalPaidAmount: old == null ? oldAmount : old.totalPaidAmount,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('റിമൈൻഡർ ചേർക്കുക', 'Add reminder'))),
    body: Form(
      key: formKey,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextFormField(controller: title,
          decoration: InputDecoration(labelText: tr('പേര് / വിശദാംശം', 'Name / Description'),
            border: const OutlineInputBorder()),
          validator: (v) => v == null || v.trim().isEmpty
              ? tr('പേര് നൽകുക', 'Enter a name') : null),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: category,
          decoration: InputDecoration(labelText: tr('വിഭാഗം', 'Category'),
            border: const OutlineInputBorder()),
          items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => category = v ?? 'Other')),
        const SizedBox(height: 12),
        TextFormField(controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('തുക (₹)', 'Amount (₹)'),
            border: const OutlineInputBorder()),
          validator: (v) {
            final n = double.tryParse(v ?? '');
            return n == null || n < 0 ? tr('ശരിയായ തുക നൽകുക', 'Enter a valid amount') : null;
          }),
        const SizedBox(height: 16),
        Text(tr('ആവർത്തനം', 'Repeat frequency'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: frequency,
          decoration: InputDecoration(labelText: tr('എത്ര ഇടവിട്ട്?', 'Repeat every'),
            border: const OutlineInputBorder()),
          items: frequencies.map((v) => DropdownMenuItem(value: v,
            child: Text(v == 'One Time' ? tr('ഒരിക്കൽ മാത്രം', v) :
              v == 'Daily' ? tr('ദിവസേന', v) :
              v == 'Weekly' ? tr('ആഴ്ചതോറും', v) :
              v == 'Monthly' ? tr('മാസംതോറും', v) : tr('വർഷംതോറും', v)))).toList(),
          onChanged: (v) => setState(() => frequency = v ?? 'One Time')),
        if (frequency == 'Weekly') ...[
          const SizedBox(height: 10),
          _dropdown(tr('ആഴ്ചയിലെ ദിവസം', 'Day of week'), weekday, weekdays,
              (v) => setState(() => weekday = v)),
        ],
        if (frequency == 'Monthly') ...[
          const SizedBox(height: 10),
          _dropdown(tr('മാസത്തിലെ ക്രമം', 'Monthly schedule type'),
              monthlyMode, ['Date', 'Weekday'], (v) => setState(() => monthlyMode = v)),
          if (monthlyMode == 'Date')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('ആരംഭ തീയതിയിലെ ദിവസം എല്ലാ മാസവും ഉപയോഗിക്കും.',
                  'The day number from the start date repeats every month.'))),
          if (monthlyMode == 'Weekday') ...[
            const SizedBox(height: 10),
            _dropdown(tr('ഏത് ആഴ്ച?', 'Which week?'), monthlyWeek, ordinalDays,
                (v) => setState(() => monthlyWeek = v)),
            const SizedBox(height: 10),
            _dropdown(tr('ഏത് ദിവസം?', 'Which weekday?'), weekday, weekdays,
                (v) => setState(() => weekday = v)),
          ],
        ],
        if (frequency == 'Yearly')
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(tr('ആരംഭ തീയതിയുടെ മാസവും ദിവസവും വർഷംതോറും ആവർത്തിക്കും.',
              'The month and day of the start date repeat yearly.'))),
        const SizedBox(height: 16),
        Text(tr('കാലാവധി (Duration)', 'Duration'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
        OutlinedButton.icon(
          onPressed: () => pickDate(start: true),
          icon: const Icon(Icons.calendar_today),
          label: Text('${tr('ആരംഭ തീയതി', 'Start date')}: ${startDate.day}/${startDate.month}/${startDate.year}')),
        if (frequency != 'One Time') ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('അവസാന തീയതി ഉപയോഗിക്കുക', 'Set end date')),
            value: useEndDate,
            onChanged: (v) => setState(() {
              useEndDate = v;
              if (v && endDate == null) {
                endDate = DateTime(startDate.year + 1, startDate.month, startDate.day);
              }
            })),
          if (useEndDate)
            OutlinedButton.icon(
              onPressed: () => pickDate(start: false),
              icon: const Icon(Icons.event),
              label: Text(endDate == null
                ? tr('അവസാന തീയതി തിരഞ്ഞെടുക്കുക', 'Choose end date')
                : '${tr('അവസാന തീയതി', 'End date')}: ${endDate!.day}/${endDate!.month}/${endDate!.year}')),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('ആകെ അടവുകളുടെ എണ്ണവും ബാക്കി തുകയും തീയതിയും ആവർത്തന രീതിയും അടിസ്ഥാനമാക്കി സ്വയം കണക്കാക്കും.',
              'Total installments and remaining balance are calculated automatically from the dates and frequency.'),
              style: const TextStyle(color: Colors.black54))),
        ],
        const SizedBox(height: 12),
        if (frequency != 'One Time') ...[
          const SizedBox(height: 18),
          Text(tr('മുൻപ് അടച്ച തുകകൾ (Existing Payment)', 'Previous payments (Existing Payment)'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            controller: previousCount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('ഇതിനകം അടച്ച തവണകളുടെ എണ്ണം', 'Installments already paid'),
              border: const OutlineInputBorder()),
            validator: (v) {
              final n = int.tryParse(v ?? '0');
              return n == null || n < 0
                ? tr('ശരിയായ എണ്ണം നൽകുക', 'Enter a valid count') : null;
            }),
          const SizedBox(height: 10),
          TextFormField(
            controller: previousAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('ഇതിനകം അടച്ച ആകെ തുക (₹)', 'Total amount already paid (₹)'),
              border: const OutlineInputBorder()),
            validator: (v) {
              final n = double.tryParse(v ?? '0');
              return n == null || n < 0
                ? tr('ശരിയായ തുക നൽകുക', 'Enter a valid amount') : null;
            }),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(tr('മുൻപത്തെ അടവുകളുടെ തീയതികൾ (ഐച്ഛികം)',
              'Previous payment dates (optional)'))),
            IconButton(onPressed: addPreviousPaymentDate,
              icon: const Icon(Icons.add_circle_outline)),
          ]),
          if (previousPaymentDates.isEmpty)
            Text(tr('തീയതികൾ ചേർക്കാത്താലും എണ്ണം, തുക എന്നിവ ഉപയോഗിച്ച് കണക്കാക്കാം.',
              'You can leave dates blank; count and amount are still recorded.'),
              style: const TextStyle(color: Colors.black54))
          else
            ...previousPaymentDates.asMap().entries.map((entry) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: Text('${entry.value.day}/${entry.value.month}/${entry.value.year}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => previousPaymentDates.removeAt(entry.key)),
              ),
            )),
        ],
        TextFormField(controller: notes, maxLines: 2,
          decoration: InputDecoration(labelText: tr('കുറിപ്പുകൾ (ഐച്ഛികം)', 'Notes (optional)'),
            border: const OutlineInputBorder())),
        if (widget.reminder != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('ഇതിനകം അടച്ചു', 'Already paid')),
            value: paid, onChanged: (v) => setState(() => paid = v)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: save,
          icon: const Icon(Icons.save),
          label: Text(tr('സേവ് ചെയ്യുക', 'Save reminder'))),
      ]),
    ),
  );

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
    value: value,
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    items: options.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
    onChanged: (v) { if (v != null) onChanged(v); },
  );
}
