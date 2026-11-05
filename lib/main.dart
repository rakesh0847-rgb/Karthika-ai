import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrmaApp());
}

class OrmaApp extends StatelessWidget {
  const OrmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ORMA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A5A44),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFAF6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFAF6),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class Reminder {
  final String id;
  String title;
  String category;
  double amount;
  DateTime dueDate;
  String notes;
  bool paid;

  Reminder({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.dueDate,
    this.notes = '',
    this.paid = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'amount': amount,
        'dueDate': dueDate.toIso8601String(),
        'notes': notes,
        'paid': paid,
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'Other',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '') ??
            DateTime.now(),
        notes: json['notes'] as String? ?? '',
        paid: json['paid'] as bool? ?? false,
      );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const String _storageKey = 'orma_reminders_v1';
  List<Reminder> _reminders = [];
  bool _loading = true;
  bool _malayalam = true;
  String _assistantName = 'കാർത്തിക';

  String tr(String ml, String en) => _malayalam ? ml : en;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _reminders = decoded
            .map((item) => Reminder.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (_) {
        _reminders = [];
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_reminders.map((item) => item.toJson()).toList()),
    );
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isOverdue(Reminder item) =>
      !item.paid && _dateOnly(item.dueDate).isBefore(_dateOnly(DateTime.now()));

  List<Reminder> get _pending =>
      _reminders.where((item) => !item.paid).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  double get _monthDue {
    final now = DateTime.now();
    return _reminders
        .where((item) =>
            !item.paid &&
            item.dueDate.year == now.year &&
            item.dueDate.month == now.month)
        .fold(0, (sum, item) => sum + item.amount);
  }

  Future<void> _openForm({Reminder? reminder}) async {
    final result = await Navigator.push<Reminder>(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderFormScreen(
          malayalam: _malayalam,
          reminder: reminder,
        ),
      ),
    );

    if (result == null) return;
    setState(() {
      final index = _reminders.indexWhere((item) => item.id == result.id);
      if (index >= 0) {
        _reminders[index] = result;
      } else {
        _reminders.add(result);
      }
    });
    await _saveReminders();
  }

  Future<void> _togglePaid(Reminder item) async {
    setState(() => item.paid = !item.paid);
    await _saveReminders();
  }

  Future<void> _delete(Reminder item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('റിമൈൻഡർ നീക്കണോ?', 'Delete reminder?')),
        content: Text(tr('ഈ രേഖ സ്ഥിരമായി നീക്കം ചെയ്യും.',
            'This reminder will be permanently deleted.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('വേണ്ട', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('നീക്കുക', 'Delete')),
          ),
        ],
      ),
    );
    if (yes == true) {
      setState(() => _reminders.removeWhere((r) => r.id == item.id));
      await _saveReminders();
    }
  }

  Future<void> _settings() async {
    final controller = TextEditingController(text: _assistantName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('അസിസ്റ്റന്റിന്റെ പേര്', 'Assistant name')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: tr('നിങ്ങൾക്ക് ഇഷ്ടമുള്ള പേര്', 'Choose a name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('റദ്ദാക്കുക', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr('സേവ്', 'Save')),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _assistantName = result);
    }
  }

  String _money(double amount) =>
      '₹${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final overdueCount = _pending.where(_isOverdue).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ഓർമ്മ  ORMA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _malayalam = !_malayalam),
            child: Text(_malayalam ? 'EN' : 'മലയാളം'),
          ),
          IconButton(
            onPressed: _settings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr('ക്രമീകരണങ്ങൾ', 'Settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: Text(tr('റിമൈൻഡർ ചേർക്കുക', 'Add reminder')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReminders,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _assistantCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          tr('ഈ മാസത്തെ അടവ്', 'Due this month'),
                          _money(_monthDue),
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          tr('കുടിശ്ശിക', 'Overdue'),
                          '$overdueCount',
                          Icons.warning_amber_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    tr('അടുത്ത അടവുകൾ', 'Upcoming payments'),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (_pending.isEmpty)
                    _emptyState()
                  else
                    ..._pending.map(_reminderCard),
                  const SizedBox(height: 20),
                  Text(
                    tr('എല്ലാ റിമൈൻഡറുകളും', 'All reminders'),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_reminders.isEmpty)
                    Text(
                      tr('ആദ്യത്തെ റിമൈൻഡർ ചേർക്കൂ.',
                          'Add your first reminder.'),
                      style: const TextStyle(color: Colors.black54),
                    )
                  else
                    ..._reminders.where((item) => item.paid).map(_reminderCard),
                ],
              ),
            ),
    );
  }

  Widget _assistantCard() {
    return Card(
      elevation: 0,
      color: const Color(0xFFF1E5DA),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/karthika.jpg',
                width: 82,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 82,
                  height: 96,
                  color: Colors.white,
                  child: const Icon(Icons.person, size: 42),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('നമസ്കാരം! ഞാൻ $_assistantName',
                        'Hello! I am $_assistantName'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tr('നിങ്ങളുടെ പ്രധാനപ്പെട്ട കാര്യങ്ങൾ ഇനി മറക്കേണ്ട.',
                        'Let me help you remember what matters.'),
                    style: const TextStyle(height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 9),
            Text(title, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.event_available, size: 42, color: Colors.green),
            const SizedBox(height: 8),
            Text(tr('ഇപ്പോൾ അടവുകൾ ഒന്നുമില്ല',
                'No upcoming payments yet')),
          ],
        ),
      ),
    );
  }

  Widget _reminderCard(Reminder item) {
    final overdue = _isOverdue(item);
    final status = item.paid
        ? tr('അടച്ചു', 'PAID')
        : overdue
            ? tr('കുടിശ്ശിക', 'OVERDUE')
            : tr('അടയ്ക്കാനുണ്ട്', 'PENDING');
    final color = item.paid
        ? Colors.green
        : overdue
            ? Colors.red
            : Colors.orange.shade800;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.12),
          child: Icon(
            item.paid ? Icons.check : Icons.event_note,
            color: color,
          ),
        ),
        title: Text(item.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${item.category} • ${item.dueDate.day}/${item.dueDate.month}/${item.dueDate.year}\n$status',
          style: TextStyle(color: color, height: 1.5),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _openForm(reminder: item);
            if (value == 'paid') _togglePaid(item);
            if (value == 'delete') _delete(item);
          },
          itemBuilder: (_) => [
            if (!item.paid)
              PopupMenuItem(
                value: 'paid',
                child: Text(tr('അടച്ചതായി രേഖപ്പെടുത്തുക', 'Mark as paid')),
              ),
            PopupMenuItem(
                value: 'edit', child: Text(tr('തിരുത്തുക', 'Edit'))),
            PopupMenuItem(
                value: 'delete', child: Text(tr('നീക്കം ചെയ്യുക', 'Delete'))),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openForm(reminder: item),
      ),
    );
  }
}

class ReminderFormScreen extends StatefulWidget {
  final bool malayalam;
  final Reminder? reminder;

  const ReminderFormScreen({
    super.key,
    required this.malayalam,
    this.reminder,
  });

  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late String _category;
  late DateTime _date;
  late bool _paid;

  bool get ml => widget.malayalam;
  String tr(String a, String b) => ml ? a : b;

  final List<String> _categories = [
    'EMI',
    'Loan',
    'Chitty',
    'Electricity',
    'Water',
    'Insurance',
    'Rent',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.reminder;
    _title = TextEditingController(text: item?.title ?? '');
    _amount = TextEditingController(
        text: item == null ? '' : item.amount.toStringAsFixed(2));
    _notes = TextEditingController(text: item?.notes ?? '');
    _category = item?.category ?? 'EMI';
    _date = item?.dueDate ?? DateTime.now();
    _paid = item?.paid ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final item = Reminder(
      id: widget.reminder?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      category: _category,
      amount: double.parse(_amount.text.trim()),
      dueDate: _date,
      notes: _notes.text.trim(),
      paid: _paid,
    );
    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('റിമൈൻഡർ', 'Reminder')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: tr('പേര് / വിശദാംശം', 'Name / Description'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.edit_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? tr('പേര് നൽകുക', 'Enter a name')
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                labelText: tr('വിഭാഗം', 'Category'),
                border: const OutlineInputBorder(),
              ),
              items: _categories
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _category = value ?? 'Other'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('തുക (₹)', 'Amount (₹)'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.currency_rupee),
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount < 0) {
                  return tr('ശരിയായ തുക നൽകുക', 'Enter a valid amount');
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text(
                '${tr('അടയ്ക്കേണ്ട തീയതി', 'Due date')}: ${_date.day}/${_date.month}/${_date.year}',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: tr('കുറിപ്പുകൾ (ഐച്ഛികം)', 'Notes (optional)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('ഇതിനകം അടച്ചു', 'Already paid')),
              value: _paid,
              onChanged: (value) => setState(() => _paid = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(tr('സേവ് ചെയ്യുക', 'Save reminder')),
            ),
          ],
        ),
      ),
    );
  }
}
