import 'dart:io';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('appBox');

  try {
    await TFLiteService.loadModels();
  } catch (e) {
    debugPrint("Model yükleme hatası: $e");
  }

  runApp(const CiltKurulukApp());
}

class CiltKurulukApp extends StatelessWidget {
  const CiltKurulukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cilt Kuruluk Analizi',
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFEFF7FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF45A7F5),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          foregroundColor: Color(0xFF132A55),
          titleTextStyle: TextStyle(
            color: Color(0xFF132A55),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class UserInfo {
  final String name;
  final String email;
  final String password;
  final DateTime birthDate;
  final double height;
  final double weight;

  UserInfo({
    required this.name,
    required this.email,
    required this.password,
    required this.birthDate,
    required this.height,
    required this.weight,
  });

  int get age {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  double get dailyWaterLiter => weight * 35 / 1000;

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'password': password,
    'birthDate': birthDate.toIso8601String(),
    'height': height,
    'weight': weight,
  };

  factory UserInfo.fromMap(Map map) {
    return UserInfo(
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      password: map['password'] ?? '',
      birthDate: DateTime.parse(map['birthDate']),
      height: (map['height'] as num).toDouble(),
      weight: (map['weight'] as num).toDouble(),
    );
  }
}

class Measurement {
  final String type;
  final double score;
  final double confidence;
  final DateTime date;

  Measurement({
    required this.type,
    required this.score,
    required this.confidence,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
    'type': type,
    'score': score,
    'confidence': confidence,
    'date': date.toIso8601String(),
  };

  factory Measurement.fromMap(Map map) {
    return Measurement(
      type: map['type'] ?? '',
      score: (map['score'] as num).toDouble(),
      confidence:
      map['confidence'] == null ? 0.0 : (map['confidence'] as num).toDouble(),
      date: DateTime.parse(map['date']),
    );
  }
}
class WaterTracking {
  final bool morning;
  final bool noon;
  final bool evening;

  WaterTracking({
    required this.morning,
    required this.noon,
    required this.evening,
  });

  int get completedCount {
    int count = 0;
    if (morning) count++;
    if (noon) count++;
    if (evening) count++;
    return count;
  }

  Map<String, dynamic> toMap() => {
    'morning': morning,
    'noon': noon,
    'evening': evening,
  };

  factory WaterTracking.fromMap(Map map) {
    return WaterTracking(
      morning: map['morning'] ?? false,
      noon: map['noon'] ?? false,
      evening: map['evening'] ?? false,
    );
  }

  WaterTracking copyWith({
    bool? morning,
    bool? noon,
    bool? evening,
  }) {
    return WaterTracking(
      morning: morning ?? this.morning,
      noon: noon ?? this.noon,
      evening: evening ?? this.evening,
    );
  }
}
class DatabaseService {
  static Box get box => Hive.box('appBox');

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static void saveUser(UserInfo user) {
    final email = _normalizeEmail(user.email);
    box.put('user_$email', user.toMap());
    box.put('lastUserEmail', email);
  }

  static UserInfo? getUser() {
    final email = box.get('lastUserEmail');
    if (email == null) return null;

    final data = box.get('user_$email');
    if (data == null) return null;

    return UserInfo.fromMap(Map<String, dynamic>.from(data));
  }

  static UserInfo? getUserByEmail(String email) {
    final normalizedEmail = _normalizeEmail(email);
    final data = box.get('user_$normalizedEmail');
    if (data == null) return null;

    return UserInfo.fromMap(Map<String, dynamic>.from(data));
  }

  static void setLastUser(String email) {
    box.put('lastUserEmail', _normalizeEmail(email));
  }

  static String _measurementKey(String email) =>
      'measurements_${_normalizeEmail(email)}';

  static void saveMeasurement(String email, Measurement measurement) {
    final list = getMeasurements(email);
    list.insert(0, measurement);

    box.put(
      _measurementKey(email),
      list.map((e) => e.toMap()).toList(),
    );
  }

  static List<Measurement> getMeasurements(String email) {
    final data = box.get(_measurementKey(email), defaultValue: []);
    return List.from(data)
        .map((e) => Measurement.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static void clearMeasurements(String email) {
    box.delete(_measurementKey(email));
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  static String _waterKey(String email) {
    return 'water_${_normalizeEmail(email)}_${_todayKey()}';
  }

  static String _waterTotalPointKey(String email) {
    return 'water_total_point_${_normalizeEmail(email)}';
  }

  static WaterTracking getTodayWaterTracking(String email) {
    final data = box.get(_waterKey(email));

    if (data == null) {
      return WaterTracking(
        morning: false,
        noon: false,
        evening: false,
      );
    }

    return WaterTracking.fromMap(Map<String, dynamic>.from(data));
  }

  static void saveTodayWaterTracking(String email, WaterTracking tracking) {
    box.put(_waterKey(email), tracking.toMap());
  }

  static int getWaterTotalPoint(String email) {
    return box.get(_waterTotalPointKey(email), defaultValue: 0);
  }

  static void increaseWaterPoint(String email) {
    final current = getWaterTotalPoint(email);
    box.put(_waterTotalPointKey(email), current + 1);
  }

  static void decreaseWaterPoint(String email) {
    final current = getWaterTotalPoint(email);
    if (current > 0) {
      box.put(_waterTotalPointKey(email), current - 1);
    }
  }

  static String getWaterLevel(String email) {
    final point = getWaterTotalPoint(email);

    if (point >= 30) {
      return "HydraSkin Uzmanı";
    } else if (point >= 20) {
      return "Cilt Bakım Rutini";
    } else if (point >= 10) {
      return "Düzenli Takipçi";
    } else if (point >= 5) {
      return "Başarılı Başlangıç";
    } else {
      return "Başlangıç Seviyesi";
    }
  }
}
enum AnalysisType { hand, lip }

String typeName(AnalysisType type) {
  return type == AnalysisType.lip ? "Dudak" : "El";
}
class AnalysisResult {

  final bool isValid;
  final String detectedLabel;
  final double confidence;
  final double drynessScore;
  final double threshold;

 AnalysisResult({
    required this.isValid,
    required this.detectedLabel,
    required this.confidence,
    required this.drynessScore,
    required this.threshold,
  });
}

class TFLiteService {
  static Interpreter? _validationInterpreter;
  static Interpreter? _lipInterpreter;
  static Interpreter? _handInterpreter;

  static List<String> _labels = [];
  static double _lipThreshold = 0.56;
  static double _handThreshold = 0.436;

  static Future<void> loadModels() async {
    _validationInterpreter ??= await Interpreter.fromAsset(
      'assets/models/dogrulama_modeli.tflite',
    );

    _lipInterpreter ??= await Interpreter.fromAsset(
      'assets/models/dudak_model.tflite',
    );

    _handInterpreter ??= await Interpreter.fromAsset(
      'assets/models/el_kuruluk_modeli.tflite',
    );

    final labelText =
    await rootBundle.loadString('assets/models/dogrulama_labels.txt');
    _labels = labelText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final lipText =
    await rootBundle.loadString('assets/models/dudak_threshold.txt');
    final handText =
    await rootBundle.loadString('assets/models/el_threshold.txt');

    _lipThreshold = double.tryParse(lipText.trim()) ?? 0.56;
    _handThreshold = double.tryParse(handText.trim()) ?? 0.436;
  }

  static Future<AnalysisResult> analyzeImage({
    required File imageFile,
    required AnalysisType selectedType,
  }) async {
    await loadModels();

    final validation = await _runValidationModel(imageFile);

    final detectedLabel = validation['label'] as String;
    final confidence = validation['confidence'] as double;

    final expectedLabel = selectedType == AnalysisType.hand ? 'el' : 'dudak';
    final threshold =
    selectedType == AnalysisType.hand ? _handThreshold : _lipThreshold;

    if (detectedLabel == 'gecersiz' || detectedLabel != expectedLabel) {
      return AnalysisResult(
        isValid: false,
        detectedLabel: detectedLabel,
        confidence: confidence,
        drynessScore: 0.0,
        threshold: threshold,
      );
    }

    final interpreter =
    selectedType == AnalysisType.hand ? _handInterpreter! : _lipInterpreter!;

    final drynessScore = await _runDrynessModel(
      interpreter: interpreter,
      imageFile: imageFile,
    );

    return AnalysisResult(
      isValid: true,
      detectedLabel: detectedLabel,
      confidence: confidence,
      drynessScore: drynessScore,
      threshold: threshold,
    );
  }

  static Future<Map<String, dynamic>> _runValidationModel(File imageFile) async {
    final interpreter = _validationInterpreter!;
    final input = await _prepareInput(
      imageFile: imageFile,
      interpreter: interpreter,
    );

    final outputShape = interpreter.getOutputTensor(0).shape;
    final classCount = outputShape.last;

    final output = List.generate(
      1,
          (_) => List.filled(classCount, 0.0),
    );

    interpreter.run(input, output);

    final scores = output.first.map((e) => e.toDouble()).toList();

    int bestIndex = 0;
    double bestScore = scores[0];

    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIndex = i;
      }
    }

    final label = bestIndex < _labels.length ? _labels[bestIndex] : 'gecersiz';

    return {
      'label': label,
      'confidence': bestScore.clamp(0.0, 1.0),
    };
  }

  static Future<double> _runDrynessModel({
    required Interpreter interpreter,
    required File imageFile,
  }) async {
    final input = await _prepareInput(
      imageFile: imageFile,
      interpreter: interpreter,
    );

    final outputShape = interpreter.getOutputTensor(0).shape;
    final outputSize = outputShape.last;

    final output = List.generate(
      1,
          (_) => List.filled(outputSize, 0.0),
    );

    interpreter.run(input, output);

    final result = output.first.map((e) => e.toDouble()).toList();

    if (result.length == 1) {
      return result[0].clamp(0.0, 1.0);
    }

    return result.reduce(max).clamp(0.0, 1.0);
  }

  static Future<List<List<List<List<num>>>>> _prepareInput({
    required File imageFile,
    required Interpreter interpreter,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);

    if (decodedImage == null) {
      throw Exception("Fotoğraf okunamadı.");
    }

    final inputTensor = interpreter.getInputTensor(0);
    final inputShape = inputTensor.shape;

    final height = inputShape[1];
    final width = inputShape[2];

    final resized = img.copyResize(
      decodedImage,
      width: width,
      height: height,
    );

    final isFloatInput = inputTensor.type == TensorType.float32;

    return [
      List.generate(height, (y) {
        return List.generate(width, (x) {
          final pixel = resized.getPixel(x, y);

          final r = pixel.r;
          final g = pixel.g;
          final b = pixel.b;

          if (isFloatInput) {
            return [
              r / 255.0,
              g / 255.0,
              b / 255.0,
            ];
          }

          return [
            r,
            g,
            b,
          ];
        });
      }),
    ];
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _login() {
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("E-posta ve şifre gir")),
      );
      return;
    }

    final user = DatabaseService.getUserByEmail(email);

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bu e-posta ile kayıt bulunamadı")),
      );
      return;
    }

    if (password != user.password) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Şifre hatalı")),
      );
      return;
    }

    DatabaseService.setLastUser(user.email);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainShell(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.82),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2F9BEE).withOpacity(0.22),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    size: 72,
                    color: Color(0xFF2F9BEE),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  "BetterWithWater",
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Akıllı cilt kuruluk takibi",
                  style: TextStyle(
                    color: Color(0xFF6E7F99),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 34),
                _softInput(
                  "E-posta",
                  emailController,
                  Icons.mail_outline_rounded,
                ),
                const SizedBox(height: 14),
                _softInput(
                  "Şifre",
                  passwordController,
                  Icons.lock_outline_rounded,
                  isPassword: true,
                ),
                const SizedBox(height: 24),
                _primaryButton(
                  text: "Giriş Yap",
                  onPressed: _login,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()),
                    );
                  },
                  child: const Text(
                    "Hesabın yok mu? Kayıt ol",
                    style: TextStyle(
                      color: Color(0xFF1769C2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _softInput(
    String label,
    TextEditingController controller,
    IconData icon, {
      bool isPassword = false,
      TextInputType? keyboardType,
    }) {
  return TextField(
    controller: controller,
    obscureText: isPassword,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF5B8FD9)),
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF7C95B8)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.92),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0xFF45A7F5), width: 1.4),
      ),
    ),
  );
}

Widget _primaryButton({
  required String text,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    height: 58,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2F9BEE),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();

  DateTime? birthDate;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    heightController.dispose();
    weightController.dispose();
    super.dispose();
  }

  void _register() {
    final name = nameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final password = passwordController.text.trim();
    final height = double.tryParse(heightController.text.trim().replaceAll(',', '.'));
    final weight = double.tryParse(weightController.text.trim().replaceAll(',', '.'));

    if (name.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        height == null ||
        weight == null ||
        birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lütfen tüm alanları doğru şekilde doldur"),
        ),
      );
      return;
    }

    if (!email.endsWith("@gmail.com")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lütfen geçerli bir Gmail adresi gir"),
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Şifre en az 6 karakter olmalı"),
        ),
      );
      return;
    }

    final existingUser = DatabaseService.getUserByEmail(email);

    if (existingUser != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bu Gmail adresi zaten kayıtlı"),
        ),
      );
      return;
    }

    final user = UserInfo(
      name: name,
      email: email,
      password: password,
      birthDate: birthDate!,
      height: height,
      weight: weight,
    );

    DatabaseService.saveUser(user);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainShell(user: user)),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                "Kayıt Ol",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF132A55),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Kişisel bilgilerini girerek başlayabilirsin.",
                style: TextStyle(color: Color(0xFF6E7F99)),
              ),
              const SizedBox(height: 26),
              _softInput("Ad", nameController, Icons.person_outline_rounded),
              const SizedBox(height: 14),
              _softInput("E-posta", emailController, Icons.mail_outline_rounded),
              const SizedBox(height: 14),
              _softInput(
                "Şifre",
                passwordController,
                Icons.lock_outline_rounded,
                isPassword: true,
              ),
              const SizedBox(height: 14),
              _softInput(
                "Boy (cm)",
                heightController,
                Icons.height_rounded,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _softInput(
                "Kilo (kg)",
                weightController,
                Icons.monitor_weight_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 58),
                  foregroundColor: const Color(0xFF1769C2),
                  side: const BorderSide(color: Color(0xFFB8DFFF)),
                  backgroundColor: Colors.white.withOpacity(0.8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2004),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => birthDate = picked);
                },
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                  birthDate == null
                      ? "Doğum Tarihi Seç"
                      : "${birthDate!.day}.${birthDate!.month}.${birthDate!.year}",
                ),
              ),
              const SizedBox(height: 26),
              _primaryButton(
                text: "Kayıt Ol",
                onPressed: _register,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _pageGradient() {
  return const BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color(0xFFEAF6FF),
        Color(0xFFF7FBFF),
        Color(0xFFDFF2FF),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

class MainShell extends StatefulWidget {
  final UserInfo user;

  const MainShell({super.key, required this.user});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(user: widget.user),
      AnalyzePage(user: widget.user),
      HistoryPage(user: widget.user),
      ProfilePage(user: widget.user),
    ];

    return Scaffold(
      extendBody: true,
      body: pages[index],
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Container(
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A90E2).withOpacity(0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: NavigationBar(
              selectedIndex: index,
              height: 78,
              elevation: 0,
              backgroundColor: Colors.transparent,
              indicatorColor: const Color(0xFFD9EEFF),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: (i) => setState(() => index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_rounded, color: Color(0xFF7C95B8)),
                  selectedIcon:
                  Icon(Icons.home_rounded, color: Color(0xFF1769C2)),
                  label: "Ana",
                ),
                NavigationDestination(
                  icon:
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C95B8)),
                  selectedIcon:
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF1769C2)),
                  label: "Analiz",
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded, color: Color(0xFF7C95B8)),
                  selectedIcon:
                  Icon(Icons.history_rounded, color: Color(0xFF1769C2)),
                  label: "Geçmiş",
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_rounded, color: Color(0xFF7C95B8)),
                  selectedIcon:
                  Icon(Icons.person_rounded, color: Color(0xFF1769C2)),
                  label: "Profil",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final UserInfo user;

  const DashboardPage({super.key, required this.user});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final measurements = DatabaseService.getMeasurements(user.email);
    final lastScore = measurements.isEmpty ? 0.0 : measurements.first.score * 100;

    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Merhaba, ${user.name} 👋",
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF132A55),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Bugünkü cilt durumunu takip et",
                          style: TextStyle(color: Color(0xFF6E7F99)),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white,
                    child: Text(
                      user.name.isEmpty ? "?" : user.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF1769C2),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              WaterTrackingCard(user: user),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2F9BEE),
                      Color(0xFF65C7F7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2F9BEE).withOpacity(0.28),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Son Kuruluk Skoru",
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      measurements.isEmpty
                          ? "Henüz ölçüm yok"
                          : "%${lastScore.toStringAsFixed(1)}",
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      measurements.isEmpty
                          ? "Analiz yaparak ilk ölçümünü kaydet."
                          : lastScore > 52
                          ? "Kuruluk yüksek görünüyor."
                          : "Kuruluk düşük görünüyor.",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _infoCard(
                      title: "Su Hedefi",
                      value: "${user.dailyWaterLiter.toStringAsFixed(1)} L",
                      icon: Icons.water_drop_rounded,
                      color: const Color(0xFF78D8F7),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _infoCard(
                      title: "Ölçüm",
                      value: "${measurements.length}",
                      icon: Icons.analytics_outlined,
                      color: const Color(0xFFBFD9FF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                "Haftalık Grafik",
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF132A55),
                ),
              ),
              const SizedBox(height: 12),
              MiniChartCard(user: user),
            ],
          ),
        ),
      ),
    );
  }
}
class WaterTrackingCard extends StatefulWidget {
  final UserInfo user;

  const WaterTrackingCard({super.key, required this.user});

  @override
  State<WaterTrackingCard> createState() => _WaterTrackingCardState();
}

class _WaterTrackingCardState extends State<WaterTrackingCard> {
  late WaterTracking tracking;

  @override
  void initState() {
    super.initState();
    tracking = DatabaseService.getTodayWaterTracking(widget.user.email);
  }

  void _toggle(String period) {
    if (period == "morning") {
      if (tracking.morning) return;

      tracking = tracking.copyWith(morning: true);
    } else if (period == "noon") {
      if (tracking.noon) return;

      tracking = tracking.copyWith(noon: true);
    } else if (period == "evening") {
      if (tracking.evening) return;

      tracking = tracking.copyWith(evening: true);
    }

    DatabaseService.increaseWaterPoint(widget.user.email);
    DatabaseService.saveTodayWaterTracking(widget.user.email, tracking);

    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final completed = tracking.completedCount;
    final progress = completed / 3;
    final level = DatabaseService.getWaterLevel(widget.user.email);
    final totalPoint = DatabaseService.getWaterTotalPoint(widget.user.email);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.14),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFD9EEFF),
                child: Icon(
                  Icons.water_drop_rounded,
                  color: Color(0xFF1769C2),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Bugünkü Hidrasyon Görevin",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
              ),
              Text(
                "$completed/3",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1769C2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFE6F3FF),
              color: const Color(0xFF2F9BEE),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _waterCheckButton(
                  title: "Sabah",
                  checked: tracking.morning,
                  onTap: () => _toggle("morning"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _waterCheckButton(
                  title: "Öğle",
                  checked: tracking.noon,
                  onTap: () => _toggle("noon"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _waterCheckButton(
                  title: "Akşam",
                  checked: tracking.evening,
                  onTap: () => _toggle("evening"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF6FF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFF1769C2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Seviye: $level • $totalPoint puan",
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF132A55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _waterCheckButton({
  required String title,
  required bool checked,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: checked ? const Color(0xFF2F9BEE) : const Color(0xFFEAF6FF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: checked ? const Color(0xFF2F9BEE) : const Color(0xFFB8DFFF),
        ),
      ),
      child: Column(
        children: [
          Icon(
            checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: checked ? Colors.white : const Color(0xFF1769C2),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: TextStyle(
              color: checked ? Colors.white : const Color(0xFF1769C2),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _infoCard({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.26),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
      border: Border.all(color: Colors.white.withOpacity(0.8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: color.withOpacity(0.35),
          child: Icon(icon, color: const Color(0xFF1769C2)),
        ),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Color(0xFF6E7F99))),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF132A55),
          ),
        ),
      ],
    ),
  );
}

class AnalyzePage extends StatefulWidget {
  final UserInfo user;

  const AnalyzePage({super.key, required this.user});

  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage> {
  bool isLoading = false;

  Future<void> _startAnalysis(AnalysisType type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Fotoğraf Kaynağı Seç",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded),
                  title: const Text("Kamera ile çek"),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text("Galeriden seç"),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => isLoading = true);

    try {
      final result = await TFLiteService.analyzeImage(
        imageFile: File(pickedFile.path),
        selectedType: type,
      );

      if (!mounted) return;
      setState(() => isLoading = false);

      if (!result.isValid) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Geçersiz Fotoğraf"),
            content: Text(
              "Seçilen analiz: ${typeName(type)}\n"
                  "Modelin algıladığı: ${result.detectedLabel}\n"
                  "Güvenilirlik: %${(result.confidence * 100).toStringAsFixed(1)}\n\n"
                  "Lütfen ${typeName(type).toLowerCase()} bölgesini net ve aydınlık şekilde çek.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Tamam"),
              ),
            ],
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultPage(
            user: widget.user,
            type: type,
            drynessScore: result.drynessScore,
            confidence: result.confidence,
            threshold: result.threshold,
            detectedLabel: result.detectedLabel,
            isValidPhoto: result.isValid,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Analiz sırasında hata oluştu: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 110),
                children: [
                  const Text(
                    "Analiz",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF132A55),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Fotoğraf önce doğrulanır, ardından kuruluk skoru hesaplanır.",
                    style: TextStyle(color: Color(0xFF6E7F99)),
                  ),
                  const SizedBox(height: 24),
                  _analysisCard(
                    title: "Dudak Analizi",
                    subtitle: "Dudak kuruluğunu ölç",
                    icon: Icons.face_rounded,
                    color: const Color(0xFFFFDCE8),
                    onTap: () => _startAnalysis(AnalysisType.lip),
                  ),
                  const SizedBox(height: 18),
                  _analysisCard(
                    title: "El Analizi",
                    subtitle: "El sırtı kuruluğunu ölç",
                    icon: Icons.back_hand_rounded,
                    color: const Color(0xFFD9F7F2),
                    onTap: () => _startAnalysis(AnalysisType.hand),
                  ),
                ],
              ),
              if (isLoading)
                Container(
                  color: Colors.black.withOpacity(0.18),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _analysisCard({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(32),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.55),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: color,
            child: Icon(icon, size: 34, color: const Color(0xFF132A55)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF6E7F99)),
                ),
              ],
            ),
          ),
          const Icon(Icons.camera_alt_rounded, color: Color(0xFF1769C2)),
        ],
      ),
    ),
  );
}

class ResultPage extends StatelessWidget {
  final UserInfo user;
  final AnalysisType type;
  final double drynessScore;
  final double confidence;
  final double threshold;
  final String detectedLabel;
  final bool isValidPhoto;

  const ResultPage({
    super.key,
    required this.user,
    required this.type,
    required this.drynessScore,
    required this.confidence,
    required this.threshold,
    required this.detectedLabel,
    required this.isValidPhoto,
  });

  List<Map<String, dynamic>> _getRecommendations({
    required bool high,
    required String area,
    required double confidence,
    required double waterLiter,
  }) {
    final isLip = area == "Dudak";

    if (high) {
      return [
        {
          "icon": Icons.spa_rounded,
          "title": isLip ? "Dudak Bakım Görevi" : "Nemlendirme Görevi",
          "text": isLip
              ? "Dudak bölgesinde kuruluk yüksek. Gün içinde koruyucu dudak balmı kullan ve dudaklarını yalama alışkanlığından kaçın."
              : "El bölgesinde kuruluk yüksek. Gün içinde 2-3 kez yoğun nemlendirici kullan ve ellerini yıkadıktan sonra mutlaka nemlendir.",
        },
        {
          "icon": Icons.water_drop_rounded,
          "title": "Su Takibi",
          "text":
          "Bugünkü kişisel su hedefin ${waterLiter.toStringAsFixed(1)} L. Ölçümden sonra bir bardak su içerek başlangıç yap.",
        },
        {
          "icon": Icons.light_mode_rounded,
          "title": "Çekim Kalitesi Notu",
          "text":
          "Model güvenilirliği %${(confidence * 100).toStringAsFixed(1)}. Daha net sonuç için fotoğrafı aydınlık ortamda ve yakın mesafeden çek.",
        },
        {
          "icon": Icons.calendar_month_rounded,
          "title": "Takip Önerisi",
          "text":
          "Yarın aynı saatlerde tekrar ölçüm yap. Böylece kuruluğun artıp azaldığını haftalık grafikte daha net görebilirsin.",
        },
      ];
    }

    return [
      {
        "icon": Icons.check_circle_rounded,
        "title": "Cilt Durumu İyi",
        "text": isLip
            ? "Dudak kuruluğun düşük görünüyor. Mevcut bakım rutinini koruyabilir, soğuk ve rüzgarlı havalarda koruyucu balm kullanabilirsin."
            : "El kuruluğun düşük görünüyor. Mevcut bakım rutinini koruyabilir, ellerini yıkadıktan sonra hafif nemlendirici kullanabilirsin.",
      },
      {
        "icon": Icons.water_drop_rounded,
        "title": "Su Hedefini Koru",
        "text":
        "Bugünkü kişisel su hedefin ${waterLiter.toStringAsFixed(1)} L. Düzenli su tüketimi cilt takibinde destekleyici olabilir.",
      },
      {
        "icon": Icons.trending_up_rounded,
        "title": "Haftalık Takip",
        "text":
        "Sonucun iyi olsa bile birkaç gün üst üste ölçüm yaparsan cilt durumundaki değişimi grafikte daha net görebilirsin.",
      },
      {
        "icon": Icons.verified_rounded,
        "title": "Güvenilirlik Notu",
        "text":
        "Bu ölçümde fotoğraf doğrulama güvenilirliği %${(confidence * 100).toStringAsFixed(1)} olarak hesaplandı.",
      },
    ];
  }
  Widget build(BuildContext context) {
    final high = drynessScore > threshold;
    final area = typeName(type);
    final recommendations = _getRecommendations(
      high: high,
      area: area,
      confidence: confidence,
      waterLiter: user.dailyWaterLiter,
    );

    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: high
                          ? [
                        const Color(0xFFFFB587),
                        const Color(0xFFFFDCE8),
                      ]
                          : [
                        const Color(0xFF86E7D8),
                        const Color(0xFF8ECCFF),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (high
                            ? const Color(0xFFFFB587)
                            : const Color(0xFF45A7F5))
                            .withOpacity(0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Icon(
                    high
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_rounded,
                    size: 90,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  high ? "Yüksek Kuruluk" : "Düşük Kuruluk",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "$area kuruluk skoru: %${(drynessScore * 100).toStringAsFixed(1)}",
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF6E7F99),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Fotoğraf doğrulama güvenilirliği: %${(confidence * 100).toStringAsFixed(1)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF6E7F99),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Algılanan bölge: $detectedLabel",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6E7F99),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Kullanılan eşik değeri: ${threshold.toStringAsFixed(3)}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6E7F99),
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: ListView(
                    children: [
                      const Text(
                        "Bugünkü Bakım Planın",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF132A55),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...recommendations.map(
                            (item) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4A90E2).withOpacity(0.12),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: high
                                    ? const Color(0xFFFFDCE8)
                                    : const Color(0xFFD9F7F2),
                                child: Icon(
                                  item["icon"] as IconData,
                                  color: const Color(0xFF132A55),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item["title"] as String,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF132A55),
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item["text"] as String,
                                      style: const TextStyle(
                                        color: Color(0xFF6E7F99),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _primaryButton(
                  text: "Kaydet ve Ana Sayfaya Dön",
                  onPressed: () {
                    DatabaseService.saveMeasurement(
                      user.email,
                      Measurement(
                        type: area,
                        score: drynessScore,
                        confidence: confidence,
                        date: DateTime.now(),
                      ),
                    );

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => MainShell(user: user)),
                          (_) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  final UserInfo user;

  const HistoryPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final measurements = DatabaseService.getMeasurements(user.email);

    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: measurements.isEmpty
              ? const Center(
            child: Text(
              "Henüz ölçüm yok.",
              style: TextStyle(color: Color(0xFF6E7F99)),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 110),
            itemCount: measurements.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    "Geçmiş",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF132A55),
                    ),
                  ),
                );
              }

              final m = measurements[index - 1];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4A90E2).withOpacity(0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: m.type == "Dudak"
                        ? const Color(0xFFFFDCE8)
                        : const Color(0xFFD9F7F2),
                    child: Icon(
                      m.type == "Dudak"
                          ? Icons.face_rounded
                          : Icons.back_hand_rounded,
                      color: const Color(0xFF132A55),
                    ),
                  ),
                  title: Text(
                    "${m.type} - %${(m.score * 100).toStringAsFixed(1)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF132A55),
                    ),
                  ),
                  subtitle: Text(
                    "${m.date.day}.${m.date.month}.${m.date.year} - Güvenilirlik: %${(m.confidence * 100).toStringAsFixed(1)}",
                    style: const TextStyle(color: Color(0xFF6E7F99)),
                  ),
                  trailing: Text(
                    m.score > 0.52 ? "Yüksek" : "Düşük",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: m.score > 0.52
                          ? const Color(0xFFFF8A3D)
                          : const Color(0xFF1DBF9F),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class MiniChartCard extends StatelessWidget {
  final UserInfo user;

  const MiniChartCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final all = DatabaseService.getMeasurements(user.email);
    final now = DateTime.now();
    final spots = <FlSpot>[];

    for (int i = 6; i >= 0; i--) {
      final day =
      DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final records = all
          .where(
            (m) =>
        m.date.year == day.year &&
            m.date.month == day.month &&
            m.date.day == day.day,
      )
          .toList();

      final avg = records.isEmpty
          ? 0.0
          : records.map((e) => e.score).reduce((a, b) => a + b) /
          records.length;

      spots.add(FlSpot((6 - i).toDouble(), avg * 100));
    }

    return Container(
      height: 230,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.14),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 4,
              color: const Color(0xFF2F9BEE),
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF2F9BEE).withOpacity(0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  final UserInfo user;

  const ProfilePage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _pageGradient(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 110),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Profil",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF132A55),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                              (_) => false,
                        );
                      },
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFF1769C2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white,
                  child: Text(
                    user.name.isEmpty ? "?" : user.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 34,
                      color: Color(0xFF1769C2),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF132A55),
                  ),
                ),
                Text(
                  user.email,
                  style: const TextStyle(color: Color(0xFF6E7F99)),
                ),
                const SizedBox(height: 28),
                _profileTile("Yaş", "${user.age}"),
                _profileTile("Boy", "${user.height.toStringAsFixed(0)} cm"),
                _profileTile("Kilo", "${user.weight.toStringAsFixed(0)} kg"),
                _profileTile(
                  "Günlük Su Hedefi",
                  "${user.dailyWaterLiter.toStringAsFixed(1)} L",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _profileTile(String title, String value) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF4A90E2).withOpacity(0.12),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF6E7F99))),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF132A55),
          ),
        ),
      ],
    ),
  );
}
