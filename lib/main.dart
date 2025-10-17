import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EduProApp());
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  APP                                                                       */
/* ────────────────────────────────────────────────────────────────────────── */

class EduProApp extends StatelessWidget {
  const EduProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EDUPRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.pink,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFBDBDBD), width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      routes: {
        '/': (_) => const SplashGate(),
        '/login': (_) => const LoginPage(),
        '/signup': (_) => const SignUpPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  DATA LAYER (Local "DB" with SharedPreferences)                             */
/* ────────────────────────────────────────────────────────────────────────── */

const _kUsersKey = 'edupro.users.v1';            // Map<id, UserProfile>
const _kCurrentUserIdKey = 'edupro.currentUserId.v1';

enum AuthProvider { email, google, apple }

class UserProfile {
  final String id;               // unique id (can be email for email users)
  final String? email;
  final String? fullName;
  final String? nickName;
  final String? phone;
  final String? gender;
  final DateTime? dob;
  final String? photoUrl;
  final AuthProvider provider;
  final String? passwordHash;    // demo only (plain text for simplicity)

  UserProfile({
    required this.id,
    required this.provider,
    this.email,
    this.fullName,
    this.nickName,
    this.phone,
    this.gender,
    this.dob,
    this.photoUrl,
    this.passwordHash,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'fullName': fullName,
    'nickName': nickName,
    'phone': phone,
    'gender': gender,
    'dob': dob?.toIso8601String(),
    'photoUrl': photoUrl,
    'provider': provider.name,
    'passwordHash': passwordHash,
  };

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
    id: m['id'] as String,
    email: m['email'] as String?,
    fullName: m['fullName'] as String?,
    nickName: m['nickName'] as String?,
    phone: m['phone'] as String?,
    gender: m['gender'] as String?,
    dob: m['dob'] != null ? DateTime.tryParse(m['dob'] as String) : null,
    photoUrl: m['photoUrl'] as String?,
    provider: AuthProvider.values.firstWhere(
          (p) => p.name == (m['provider'] as String? ?? 'email'),
      orElse: () => AuthProvider.email,
    ),
    passwordHash: m['passwordHash'] as String?,
  );
}

class LocalAuthService {
  LocalAuthService._();
  static final LocalAuthService instance = LocalAuthService._();

  Future<Map<String, UserProfile>> _loadUsersMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUsersKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, UserProfile.fromMap((v as Map).cast<String, dynamic>())));
  }

  Future<void> _saveUsersMap(Map<String, UserProfile> users) async {
    final prefs = await SharedPreferences.getInstance();
    final enc = jsonEncode(users.map((k, v) => MapEntry(k, v.toMap())));
    await prefs.setString(_kUsersKey, enc);
  }

  Future<void> _setCurrentUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentUserIdKey, id);
  }

  Future<String?> _getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentUserIdKey);
  }

  /* Public API */

  Future<UserProfile?> loadCurrentUser() async {
    final id = await _getCurrentUserId();
    if (id == null) return null;
    final users = await _loadUsersMap();
    return users[id];
  }

  Future<void> saveAndSetCurrentUser(UserProfile user) async {
    final users = await _loadUsersMap();
    users[user.id] = user;
    await _saveUsersMap(users);
    await _setCurrentUserId(user.id);
  }

  Future<UserProfile?> getUserByEmail(String email) async {
    final users = await _loadUsersMap();
    final e = email.trim().toLowerCase();
    for (final u in users.values) {
      if ((u.email ?? '').toLowerCase() == e) return u;
    }
    return null;
  }

  Future<bool> verifyEmailPassword(String email, String password) async {
    final user = await getUserByEmail(email);
    if (user == null) return false;
    if (user.provider != AuthProvider.email) return false; // social-only accounts don't have passwords here
    return (user.passwordHash ?? '') == password;          // demo only
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentUserIdKey); // keep users DB, clear session only
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  SPLASH GATE: auto-route to /home if a session exists                      */
/* ────────────────────────────────────────────────────────────────────────── */

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final user = await LocalAuthService.instance.loadCurrentUser();
    if (!mounted) return;
    if (user != null) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  LOGIN PAGE                                                                 */
/* ────────────────────────────────────────────────────────────────────────── */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await LocalAuthService.instance.verifyEmailPassword(_email.text, _password.text);
    if (!ok) {
      setState(() => _busy = false);
      _snack('Invalid credentials or no local account. Try Sign Up.');
      return;
    }
    // set session to that user
    final user = await LocalAuthService.instance.getUserByEmail(_email.text);
    if (user != null) {
      await LocalAuthService.instance.saveAndSetCurrentUser(user);
    }
    setState(() => _busy = false);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _continueWithGoogle() async {
    try {
      setState(() => _busy = true);

      // For web you may need to pass clientId: GoogleSignIn(clientId: 'YOUR_WEB_CLIENT_ID')
      final google = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await google.signIn();
      if (account == null) {
        setState(() => _busy = false);
        return; // user cancelled
      }
      final user = UserProfile(
        id: 'google_${account.id}',
        provider: AuthProvider.google,
        email: account.email,
        fullName: account.displayName,
        photoUrl: account.photoUrl,
      );
      await LocalAuthService.instance.saveAndSetCurrentUser(user);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      _snack('Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithApple() async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      _snack('Sign in with Apple is only available on iOS/macOS.');
      return;
    }
    try {
      setState(() => _busy = true);
      final res = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final fullName = [res.givenName ?? '', res.familyName ?? '']
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim();

      final user = UserProfile(
        id: 'apple_${res.userIdentifier ?? DateTime.now().millisecondsSinceEpoch}',
        provider: AuthProvider.apple,
        email: res.email, // may be null on subsequent logins
        fullName: fullName.isEmpty ? null : fullName,
      );
      await LocalAuthService.instance.saveAndSetCurrentUser(user);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      _snack('Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AbsorbPointer(
        absorbing: _busy,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _LogoHeader(),
                    const SizedBox(height: 24),
                    const Text("Let's Sign In.!",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Login to Your Account to Continue your Courses',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 24),

                    Form(
                      key: _formKey,
                      child: Column(children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Email is required';
                            final ok = RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim());
                            return ok ? null : 'Enter a valid email';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _remember,
                          onChanged: (v) => setState(() => _remember = v ?? false),
                        ),
                        const Text('Remember Me'),
                        const Spacer(),
                        TextButton(onPressed: () {}, child: const Text('Forgot Password?')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _GradientCTA(
                      label: _busy ? 'Please wait…' : 'Sign In',
                      onPressed: _busy ? null : _loginEmail,
                      trailingIcon: Icons.arrow_forward,
                    ),
                    const SizedBox(height: 18),

                    const _OrDivider(text: 'Or Continue With'),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SocialCircle(
                          icon: FontAwesomeIcons.google,
                          onTap: _continueWithGoogle,
                        ),
                        const SizedBox(width: 16),
                        _SocialCircle(
                          icon: FontAwesomeIcons.apple,
                          onTap: _continueWithApple,
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text("Don't have an Account? "),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/signup'),
                        child: const Text('SIGN UP'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  SIGN UP (manual or prefilled by Google/Apple)                              */
/* ────────────────────────────────────────────────────────────────────────── */

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _nickName = TextEditingController();
  final _dob = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _gender;
  bool _agree = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _fullName.dispose();
    _nickName.dispose();
    _dob.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      _dob.text =
      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _continueWithGoogle() async {
    try {
      setState(() => _busy = true);
      final google = GoogleSignIn(scopes: ['email', 'profile']);
      final account = await google.signIn();
      if (account != null) {
        _email.text = account.email;
        _fullName.text = account.displayName ?? '';
      }
    } catch (e) {
      _snack('Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithApple() async {
    if (!(Platform.isIOS || Platform.isMacOS)) {
      _snack('Sign in with Apple is only available on iOS/macOS.');
      return;
    }
    try {
      setState(() => _busy = true);
      final res = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final fullName = [res.givenName ?? '', res.familyName ?? '']
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim();
      _fullName.text = fullName;
      if (res.email != null) _email.text = res.email!;
    } catch (e) {
      _snack('Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_agree) {
      _snack('Please agree to Terms & Conditions.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final email = _email.text.trim();
    final profile = UserProfile(
      id: email.isNotEmpty ? 'email_$email' : 'local_${DateTime.now().microsecondsSinceEpoch}',
      provider: AuthProvider.email,
      email: email.isEmpty ? null : email,
      fullName: _fullName.text.trim(),
      nickName: _nickName.text.trim().isEmpty ? null : _nickName.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      gender: _gender,
      dob: _dob.text.isEmpty ? null : DateTime.tryParse(_dob.text),
      passwordHash: _password.text, // demo only
    );
    await LocalAuthService.instance.saveAndSetCurrentUser(profile);
    setState(() => _busy = false);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => Navigator.pop(context))),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _LogoHeader(),
                    const SizedBox(height: 16),
                    const Text('Getting Started.!',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('Create an Account to Continue your allCourses',
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 18),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _fullName,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Full name required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nickName,
                            decoration: const InputDecoration(
                              labelText: 'Nick Name',
                              prefixIcon: Icon(Icons.tag),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _dob,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Date of Birth',
                              prefixIcon: const Icon(Icons.cake_outlined),
                              suffixIcon: IconButton(
                                onPressed: _pickDob,
                                icon: const Icon(Icons.calendar_today_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Email required';
                              final ok = RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim());
                              return ok ? null : 'Enter a valid email';
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _gender,
                            decoration: const InputDecoration(
                              labelText: 'Gender',
                              prefixIcon: Icon(Icons.wc_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Female', child: Text('Female')),
                              DropdownMenuItem(value: 'Male', child: Text('Male')),
                              DropdownMenuItem(value: 'Other', child: Text('Other')),
                              DropdownMenuItem(
                                  value: 'Prefer not to say', child: Text('Prefer not to say')),
                            ],
                            onChanged: (v) => setState(() => _gender = v),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscure = !_obscure),
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                              ),
                            ),
                            validator: (v) =>
                            (v == null || v.length < 6) ? 'Min 6 characters' : null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Checkbox(
                                value: _agree,
                                onChanged: (v) => setState(() => _agree = v ?? false),
                              ),
                              const Expanded(child: Text('Agree to Terms & Conditions')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _GradientCTA(
                      label: _busy ? 'Please wait…' : 'Sign Up',
                      onPressed: _busy ? null : _submit,
                      trailingIcon: Icons.arrow_forward,
                    ),
                    const SizedBox(height: 16),

                    const _OrDivider(text: 'Or Continue With'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SocialCircle(
                          icon: FontAwesomeIcons.google,
                          onTap: _continueWithGoogle,
                        ),
                        const SizedBox(width: 16),
                        _SocialCircle(
                          icon: FontAwesomeIcons.apple,
                          onTap: _continueWithApple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Already have an Account? '),
                        TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                          child: const Text('SIGN IN'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  HOME (just shows stored profile & Sign Out)                                */
/* ────────────────────────────────────────────────────────────────────────── */

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  UserProfile? _user;

  @override
  void initState() {
    super.initState();
    LocalAuthService.instance.loadCurrentUser().then((u) => setState(() => _user = u));
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('EDUPRO Home')),
      body: u == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: (u.photoUrl != null) ? NetworkImage(u.photoUrl!) : null,
                child: (u.photoUrl == null) ? const Icon(Icons.person, size: 28) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.fullName ?? 'Unnamed',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(u.email ?? '(no email)'),
                  Text('Provider: ${u.provider.name}'),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              onPressed: () async {
                await LocalAuthService.instance.signOut();
                if (!mounted) return;
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  UI HELPERS                                                                 */
/* ────────────────────────────────────────────────────────────────────────── */

class _LogoHeader extends StatelessWidget {
  const _LogoHeader();

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        height: 46,
        width: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.school_outlined, color: Color(0xFF3A68FF)),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('EDUPRO', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        SizedBox(height: 2),
        Text('LEARN FROM HOME', style: TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
    ]);
  }
}

class _GradientCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData trailingIcon;
  const _GradientCTA({required this.label, required this.onPressed, required this.trailingIcon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF7BB2), Color(0xFFFF3D8B)]),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF3D8B).withOpacity(0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Stack(alignment: Alignment.center, children: [
              Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
              Positioned(
                right: 8,
                child: Container(
                  height: 38,
                  width: 38,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(trailingIcon, color: const Color(0xFFFF3D8B)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  final String text;
  const _OrDivider({required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(thickness: 1, color: Color(0xFFE0E0E0))),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    ),
    const Expanded(child: Divider(thickness: 1, color: Color(0xFFE0E0E0))),
  ]);
}

class _SocialCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SocialCircle({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Icon(icon, size: 26, color: Colors.black87),
        ),
      ),
    );
  }
}
