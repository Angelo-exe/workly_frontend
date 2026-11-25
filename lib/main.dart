import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';

/// Android Emulator: 10.0.2.2 raggiunge il PC host.
/// Smartphone fisico: sostituire con l'IP LAN del computer che esegue il backend.
///const String apiBaseUrl = 'http://10.0.2.2:8080';


/// Emulatore Android: usa 10.0.2.2.
/// Smartphone fisico via USB: usa 127.0.0.1 con adb reverse.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);

void main() => runApp(const WorklyApp());

class Api {
  static String? token;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  static Future<dynamic> request(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      } else {
        response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 30));
      }
    } on SocketException {
      throw Exception('Server non raggiungibile. Controlla che Workly Backend sia avviato e che apiBaseUrl sia corretto.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Errore di connessione: $e');
    }
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = {}; }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? (data['error'] ?? 'Errore ${response.statusCode}') : 'Errore ${response.statusCode}');
    }
    return data;
  }
}

class WorklyApp extends StatelessWidget {
  const WorklyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Workly',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  List<dynamic> jobs = [];
  String? companyName;
  String? companyEmail;

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _loadJobs();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('token');
    Api.token = savedToken;

    // Il backend conserva i token solo in memoria: dopo un suo riavvio,
    // verifica il token salvato e rimuove una sessione ormai non valida.
    if (savedToken != null && savedToken.isNotEmpty) {
      try {
        await Api.request('GET', '/api/my/jobs');
      } catch (_) {
        Api.token = null;
        await prefs.remove('token');
        await prefs.remove('companyName');
        await prefs.remove('companyEmail');
      }
    }

    if (!mounted) return;
    setState(() {
      companyName = Api.token == null ? null : prefs.getString('companyName');
      companyEmail = Api.token == null ? null : prefs.getString('companyEmail');
    });
  }

  Future<void> _loadJobs() async {
    try {
      final result = await Api.request('GET', '/api/jobs');
      if (mounted) setState(() { jobs = result as List; loading = false; });
    } catch (e) {
      if (mounted) setState(() => loading = false);
      _message(e.toString(), error: true);
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message.replaceFirst('Exception: ', '')),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Future<void> _openAuth({required bool register}) async {
    final result = await Navigator.push<Map<String, String>>(context,
        MaterialPageRoute(builder: (_) => AuthPage(register: register)));
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', result['token']!);
      await prefs.setString('companyName', result['companyName']!);
      await prefs.setString('companyEmail', result['email']!);
      Api.token = result['token'];
      setState(() {
        companyName = result['companyName'];
        companyEmail = result['email'];
        tab = 1;
      });
    }
  }

  Future<void> _logout() async {
    try { await Api.request('POST', '/api/logout'); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('companyName');
    await prefs.remove('companyEmail');
    Api.token = null;
    setState(() { companyName = null; companyEmail = null; tab = 0; });
    _message('Logout effettuato');
  }

  @override
  Widget build(BuildContext context) {
    final logged = Api.token != null && companyName != null;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.work_outline, color: Color(0xFF3157D5)),
          const SizedBox(width: 8),
          const Text('workly', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5)),
        ]),
        actions: [
          if (!logged) TextButton(onPressed: () => _openAuth(register: false), child: const Text('Accedi')),
          if (!logged) Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(onPressed: () => _openAuth(register: true), child: const Text('Registrati')),
          ),
          if (logged) PopupMenuButton<String>(
            onSelected: (v) { if (v == 'logout') _logout(); },
            itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('Esci'))],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: CircleAvatar(child: Text(companyName![0].toUpperCase()))),
          ),
        ],
      ),
      body: tab == 0
          ? _publicBody()
          : logged ? CompanyPage(companyName: companyName!, email: companyEmail!, onChanged: _loadJobs, onMessage: (message, isError) => _message(message, error: isError))
          : _publicBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) {
          if (v == 1 && !logged) {
            _openAuth(register: false);
          } else { setState(() => tab = v); }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Annunci'),
          NavigationDestination(icon: Icon(Icons.business_center_outlined), label: 'Azienda'),
        ],
      ),
      floatingActionButton: tab == 0 ? FloatingActionButton(
        onPressed: _loadJobs, tooltip: 'Aggiorna annunci', child: const Icon(Icons.refresh),
      ) : null,
    );
  }

  Widget _publicBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: jobs.isEmpty
          ? ListView(children: const [SizedBox(height: 130), Icon(Icons.work_off_outlined, size: 64, color: Colors.grey), SizedBox(height: 16), Center(child: Text('Nessun annuncio disponibile'))])
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          const Text('Trova il tuo prossimo lavoro', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${jobs.length} opportunità pubblicate', style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 18),
          ...jobs.map((j) => JobCard(job: Map<String, dynamic>.from(j), onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(job: Map<String, dynamic>.from(j))));
          })),
        ],
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;
  const JobCard({super.key, required this.job, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.grey.shade200)),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xFFE9EDFF), child: const Icon(Icons.business, color: Color(0xFF3157D5))),
            const SizedBox(width: 10),
            Expanded(child: Text(job['companyName'] ?? 'Azienda', style: const TextStyle(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right),
          ]),
          const SizedBox(height: 13),
          Text(job['title'] ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(job['description'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, height: 1.4)),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerRight, child: Text('Scopri di più  →', style: TextStyle(color: Color(0xFF3157D5), fontWeight: FontWeight.w700))),
        ]),
      ),
    ),
  );
}

class JobDetailPage extends StatelessWidget {
  final Map<String, dynamic> job;
  const JobDetailPage({super.key, required this.job});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dettaglio annuncio')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.work_outline, size: 52, color: Color(0xFF3157D5)),
      const SizedBox(height: 18),
      Text(job['title'] ?? '', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(job['companyName'] ?? '', style: const TextStyle(fontSize: 16, color: Color(0xFF3157D5), fontWeight: FontWeight.w600)),
      const SizedBox(height: 24),
      const Text('Descrizione della posizione', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(job['description'] ?? '', style: const TextStyle(fontSize: 16, height: 1.6)),
      const SizedBox(height: 32),
      FilledButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApplyPage(job: job))),
        icon: const Icon(Icons.send),
        label: const Text('Candidati a questa offerta'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
      ),
    ]),
  );
}

class ApplyPage extends StatefulWidget {
  final Map<String, dynamic> job;
  const ApplyPage({super.key, required this.job});
  @override
  State<ApplyPage> createState() => _ApplyPageState();
}
class _ApplyPageState extends State<ApplyPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), surname = TextEditingController(), email = TextEditingController();
  PlatformFile? cv;
  bool sending = false;

  Future<void> _pickCv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => cv = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    if (cv == null || cv!.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allega il curriculum in PDF')));
      return;
    }
    if (cv!.size > 8 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Il PDF supera il limite di 8 MB')));
      return;
    }
    setState(() => sending = true);
    try {
      await Api.request('POST', '/api/jobs/${widget.job['id']}/applications', body: {
        'name': name.text.trim(), 'surname': surname.text.trim(), 'email': email.text.trim(),
        'cvName': cv!.name, 'cvBase64': base64Encode(cv!.bytes!),
      });
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Candidatura inviata!'),
        content: const Text('La tua candidatura è stata registrata correttamente.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Perfetto'))],
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override
  void dispose() { name.dispose(); surname.dispose(); email.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invia candidatura')),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.job['title'] ?? '', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Inserisci i tuoi dati e allega il curriculum. Non è necessario creare un account.'),
      const SizedBox(height: 22),
      _field(name, 'Nome'),
      const SizedBox(height: 14),
      _field(surname, 'Cognome'),
      const SizedBox(height: 14),
      _field(email, 'Email', type: TextInputType.emailAddress, validator: (v) => v != null && v.contains('@') ? null : 'Inserisci un indirizzo email valido'),
      const SizedBox(height: 20),
      OutlinedButton.icon(onPressed: _pickCv, icon: const Icon(Icons.picture_as_pdf), label: Text(cv == null ? 'Allega curriculum PDF' : cv!.name), style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16))),
      const SizedBox(height: 8),
      Text('Formato PDF · massimo 8 MB', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      const SizedBox(height: 26),
      FilledButton(onPressed: sending ? null : _submit, style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)), child: sending ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Conferma candidatura')),
    ])),
  );
}

Widget _field(TextEditingController controller, String label, {TextInputType type = TextInputType.text, String? Function(String?)? validator}) =>
    TextFormField(controller: controller, keyboardType: type, decoration: InputDecoration(labelText: label), validator: validator ?? (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null);

class AuthPage extends StatefulWidget {
  final bool register;
  const AuthPage({super.key, required this.register});
  @override
  State<AuthPage> createState() => _AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
final form = GlobalKey<FormState>();
final company = TextEditingController(), email = TextEditingController(), password = TextEditingController();
bool busy = false, obscure = true;
String? error;

Future<void> _submit() async {
if (!form.currentState!.validate()) return;
setState(() { busy = true; error = null; });
try {
if (widget.register) {
await Api.request('POST', '/api/register', body: {'companyName': company.text.trim(), 'email': email.text.trim(), 'password': password.text});
}
final result = await Api.request('POST', '/api/login', body: {'email': email.text.trim(), 'password': password.text});
if (!mounted) return;
Navigator.pop(context, {
'token': result['token'].toString(),
'companyName': result['company']['companyName'].toString(),
'email': result['company']['email'].toString(),
});
} catch (e) {
if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
} finally { if (mounted) setState(() => busy = false); }
}

@override
void dispose() { company.dispose(); email.dispose(); password.dispose(); super.dispose(); }
@override
Widget build(BuildContext context) => Scaffold(
appBar: AppBar(title: Text(widget.register ? 'Crea account aziendale' : 'Accesso azienda')),
body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(22), child: Card(
color: Colors.white, elevation: 0, child: Padding(padding: const EdgeInsets.all(22), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
const Icon(Icons.business_center, size: 54, color: Color(0xFF3157D5)),
const SizedBox(height: 12),
Text(widget.register ? 'Benvenuta su Workly' : 'Bentornata su Workly', textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Text(widget.register ? 'Registra la tua azienda per pubblicare annunci.' : 'Accedi per gestire annunci e candidature.', textAlign: TextAlign.center),
const SizedBox(height: 24),
if (widget.register) ...[
TextFormField(controller: company, decoration: const InputDecoration(labelText: 'Nome azienda'), validator: (v) => v == null || v.trim().isEmpty ? 'Inserisci il nome azienda' : null),
const SizedBox(height: 14),
],
TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => v != null && v.contains('@') ? null : 'Email non valida'),
const SizedBox(height: 14),
TextFormField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => obscure = !obscure))), validator: (v) => v != null && v.length >= 6 ? null : 'Minimo 6 caratteri'),
if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.red))],
const SizedBox(height: 22),
FilledButton(onPressed: busy ? null : _submit, style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)), child: busy ? const CircularProgressIndicator() : Text(widget.register ? 'Registrati e accedi' : 'Accedi')),
]))),
)),
));
}

class CompanyPage extends StatefulWidget {
  final String companyName, email;
  final VoidCallback onChanged;
  final void Function(String message, bool isError) onMessage;
  const CompanyPage({super.key, required this.companyName, required this.email, required this.onChanged, required this.onMessage});
  @override
  State<CompanyPage> createState() => _CompanyPageState();
}
class _CompanyPageState extends State<CompanyPage> {
  List<dynamic> myJobs = [];
  bool loading = true;
  @override
  void initState() { super.initState(); _loadMine(); }

  Future<void> _loadMine() async {
    try {
      final mine = await Api.request('GET', '/api/my/jobs') as List;
      if (mounted) setState(() { myJobs = mine; loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        widget.onMessage(e.toString(), true);
      }
    }
  }


  Future<void> _createJob() async {
    if (!mounted) return;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const CreateJobDialog(),
    );

    if (!mounted || created != true) return;

    await _loadMine();

    if (!mounted) return;

    widget.onChanged();

    widget.onMessage(
      'Annuncio pubblicato correttamente',
      false,
    );
  }


  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _loadMine,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Ciao, ${widget.companyName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(widget.email, style: TextStyle(color: Colors.grey.shade700)),
      const SizedBox(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('I tuoi annunci', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        FilledButton.icon(onPressed: _createJob, icon: const Icon(Icons.add), label: const Text('Nuovo')),
      ]),
      const SizedBox(height: 12),
      if (loading) const Center(child: CircularProgressIndicator())
      else if (myJobs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Non hai ancora pubblicato annunci.', textAlign: TextAlign.center))
      else ...myJobs.map((j) => Card(
          color: Colors.white, elevation: 0, child: ListTile(
          title: Text(j['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Visualizza le candidature ricevute'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApplicationsPage(job: Map<String, dynamic>.from(j)))),
        ),
        )),
    ]),
  );
}


class CreateJobDialog extends StatefulWidget {
  const CreateJobDialog({super.key});

  @override
  State<CreateJobDialog> createState() =>
      _CreateJobDialogState();
}

class _CreateJobDialogState extends State<CreateJobDialog> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    if (_sending) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await Api.request(
        'POST',
        '/api/jobs',
        body: {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _sending = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo annuncio'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titolo',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Obbligatorio';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'Descrizione',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Obbligatoria';
                    }
                    return null;
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),

        FilledButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : const Text('Pubblica'),
        ),
      ],
    );
  }
}




class ApplicationsPage extends StatefulWidget {
  final Map<String, dynamic> job;
  const ApplicationsPage({super.key, required this.job});
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}
class _ApplicationsPageState extends State<ApplicationsPage> {
  List<dynamic> applications = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final result = await Api.request('GET', '/api/jobs/${widget.job['id']}/applications') as List;
      if (mounted) setState(() { applications = result; loading = false; });
    } catch (e) { if (mounted) setState(() { error = e.toString(); loading = false; }); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Candidature ricevute')),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null
        ? Center(child: Text(error!))
        : applications.isEmpty
        ? const Center(child: Text('Ancora nessuna candidatura per questo annuncio.'))
        : ListView(padding: const EdgeInsets.all(16), children: [
      Text(widget.job['title'], style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      ...applications.map((a) => Card(color: Colors.white, elevation: 0, child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text('${a['name']} ${a['surname']}'),
        subtitle: Text(a['email']),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApplicantPage(application: Map<String, dynamic>.from(a)))),
      ))),
    ]),
  );
}

class ApplicantPage extends StatelessWidget {
  final Map<String, dynamic> application;
  const ApplicantPage({super.key, required this.application});
  Future<void> _openCv(BuildContext context) async {
    final uri = Uri.parse('$apiBaseUrl/api/applications/${application['id']}/cv');
    try {
      final response = await http.get(uri, headers: Api.headers);
      if (response.statusCode != 200) throw Exception('Impossibile aprire il curriculum (${response.statusCode})');
      // Per la massima compatibilità, apre il PDF tramite un URL autenticato non disponibile
      // ai visualizzatori esterni: il file viene salvato temporaneamente e condiviso/aperto.
      final dir = await Directory.systemTemp.createTemp('workly_cv_');
      final file = File('${dir.path}/curriculum.pdf');
      await file.writeAsBytes(response.bodyBytes);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF scaricato: ${result.message}')));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dettaglio candidato')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const CircleAvatar(radius: 38, child: Icon(Icons.person, size: 40)),
      const SizedBox(height: 18),
      Text('${application['name']} ${application['surname']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      Card(color: Colors.white, elevation: 0, child: Column(children: [
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('Nome e cognome'), subtitle: Text('${application['name']} ${application['surname']}')),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(application['email'])),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.picture_as_pdf), title: const Text('Curriculum'), subtitle: Text(application['cvName'] ?? 'curriculum.pdf')),
      ])),
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: () => _openCv(context), icon: const Icon(Icons.open_in_new), label: const Text('Apri curriculum PDF'), style: FilledButton.styleFrom(padding: const EdgeInsets.all(16))),
    ]),
  );
}
