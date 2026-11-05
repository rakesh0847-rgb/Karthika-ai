
import 'package:flutter/material.dart';

void main() {
  runApp(const KarthikaAI());
}

class KarthikaAI extends StatelessWidget {
  const KarthikaAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Karthika AI',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF9C426E),
        scaffoldBackgroundColor: const Color(0xFFFFF8FA),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool malayalam = true;

  @override
  Widget build(BuildContext context) {
    final title = malayalam ? 'ഹായ്! ഞാൻ കാർത്തിക' : 'Hi! I am Karthika';
    final subtitle = malayalam
        ? 'നിങ്ങളുടെ സ്വന്തം AI Assistant'
        : 'Your Personal AI Assistant';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KARTHIKA AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => malayalam = !malayalam);
            },
            child: Text(malayalam ? 'EN' : 'മലയാളം'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Image.asset(
                'assets/karthika.jpg',
                width: 230,
                height: 260,
                fit: BoxFit.cover,
             ),
           ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 30),
            _sectionTitle(
              malayalam ? 'എന്നോട് സംസാരിക്കൂ' : 'Talk with me',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _actionCard(
                    Icons.chat_bubble_outline,
                    'Chat',
                    malayalam ? 'ടൈപ്പ് ചെയ്യുക' : 'Type a message',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(malayalam: malayalam),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionCard(
                    Icons.mic_none,
                    malayalam ? 'Voice' : 'Voice',
                    malayalam ? 'സംസാരിക്കുക' : 'Speak with me',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            _sectionTitle(
              malayalam ? 'നിങ്ങളുടെ അസിസ്റ്റന്റ്' : 'Your Assistant',
            ),
            const SizedBox(height: 14),
            _menuTile(
              Icons.person_outline,
              malayalam ? 'Personal Assistant' : 'Personal Assistant',
            ),
            _menuTile(
              Icons.business_center_outlined,
              malayalam ? 'Business Assistant' : 'Business Assistant',
            ),
            _menuTile(
              Icons.video_camera_front_outlined,
              malayalam ? 'AI Video Presenter' : 'AI Video Presenter',
            ),
            _menuTile(
              Icons.settings_outlined,
              malayalam ? 'Settings' : 'Settings',
            ),
            const SizedBox(height: 25),
            const Text(
              'KARTHIKA AI • Version 1.0',
              style: TextStyle(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _actionCard(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 35, color: const Color(0xFF9C426E)),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(
                fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String title) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF9C426E)),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}


class ChatScreen extends StatefulWidget {
  final bool malayalam;

  const ChatScreen({super.key, required this.malayalam});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': message});
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karthika Chat'),
        backgroundColor: const Color(0xFFFFF8FA),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      widget.malayalam
                          ? 'ഹായ്! ഞാൻ കാർത്തിക. എന്നോട് സംസാരിക്കൂ.'
                          : 'Hi! I am Karthika. Start a conversation.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final isUser = item['role'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? const Color(0xFFEFD7E2)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(item['text'] ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: widget.malayalam
                            ? 'സന്ദേശം എഴുതുക...'
                            : 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF9C426E),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
