// lib/main.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// Social providers
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/* ────────────────────────────────────────────────────────────────────────── */
/*  MAIN                                                                       */
/* ────────────────────────────────────────────────────────────────────────── */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
/*  FIREBASE SHORTCUTS + PROFILE UPSERT                                        */
/* ────────────────────────────────────────────────────────────────────────── */

final _auth = FirebaseAuth.instance;
final _db = FirebaseFirestore.instance;

Future<void> _upsertUserProfile({
  required User user,
  String? fullName,
  String? nickName,
  String? phone,
  String? gender,
  DateTime? dob,
  String? photoUrl,
}) async {
  final doc = _db.collection('users').doc(user.uid);
  final data = <String, dynamic>{
    'email': user.email,
    'fullName': fullName ?? user.displayName,
    'nickName': nickName,
    'phone': phone,
    'gender': gender,
    'dob': dob?.toIso8601String(),
    'photoUrl': photoUrl ?? user.photoURL,
    'providerIds': user.providerData.map((p) => p.providerId).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  }..removeWhere((_, v) => v == null);
  await doc.set(data, SetOptions(merge: true));
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  SPLASH GATE                                                                */
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
    _auth.authStateChanges().listen((user) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, user == null ? '/login' : '/home');
    });
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
  bool _remember = false; // Firebase persists session anyway
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Email login failed');
    } catch (e) {
      _snack('Email login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        final cred = await _auth.signInWithPopup(GoogleAuthProvider());
        await _upsertUserProfile(user: cred.user!);
      } else {
        final g = gsi.GoogleSignIn(scopes: const ['email', 'profile']);
        final account = await g.signIn();
        if (account == null) return; // cancelled
        final auth = await account.authentication;
        final credential = GoogleAuthProvider.credential(
          idToken: auth.idToken,
          accessToken: auth.accessToken,
        );
        final userCred = await _auth.signInWithCredential(credential);
        await _upsertUserProfile(user: userCred.user!);
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Google sign-in failed');
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
    setState(() => _busy = true);
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauth = OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        accessToken: apple.authorizationCode,
      );
      final userCred = await _auth.signInWithCredential(oauth);
      final fullName = [apple.givenName ?? '', apple.familyName ?? '']
          .where((s) => s.isNotEmpty).join(' ').trim();
      await _upsertUserProfile(
        user: userCred.user!,
        fullName: fullName.isEmpty ? null : fullName,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Apple sign-in failed');
    } catch (e) {
      _snack('Apple sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
/*  SIGN UP PAGE                                                               */
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

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    setState(() => _busy = true);
    try {
      if (kIsWeb) {
        final cred = await _auth.signInWithPopup(GoogleAuthProvider());
        await _upsertUserProfile(user: cred.user!);
        _email.text = cred.user?.email ?? _email.text;
        _fullName.text = cred.user?.displayName ?? _fullName.text;
      } else {
        final g = gsi.GoogleSignIn(scopes: const ['email', 'profile']);
        final account = await g.signIn();
        if (account != null) {
          final auth = await account.authentication;
          final credential = GoogleAuthProvider.credential(
            idToken: auth.idToken,
            accessToken: auth.accessToken,
          );
          final userCred = await _auth.signInWithCredential(credential);
          await _upsertUserProfile(user: userCred.user!);
          _email.text = userCred.user?.email ?? '';
          _fullName.text = userCred.user?.displayName ?? '';
        }
      }
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Google sign-in failed');
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
    setState(() => _busy = true);
    try {
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      final oauth = OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        accessToken: apple.authorizationCode,
      );
      final userCred = await _auth.signInWithCredential(oauth);
      final fullName = [apple.givenName ?? '', apple.familyName ?? '']
          .where((s) => s.isNotEmpty).join(' ').trim();
      await _upsertUserProfile(
        user: userCred.user!,
        fullName: fullName.isEmpty ? null : fullName,
      );

      _email.text = userCred.user?.email ?? _email.text;
      _fullName.text = fullName.isEmpty ? _fullName.text : fullName;
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Apple sign-in failed');
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
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      await _upsertUserProfile(
        user: cred.user!,
        fullName: _fullName.text.trim(),
        nickName: _nickName.text.trim().isEmpty ? null : _nickName.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        gender: _gender,
        dob: _dob.text.isEmpty ? null : DateTime.tryParse(_dob.text),
      );

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? 'Sign up failed');
    } catch (e) {
      _snack('Sign up failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
      ),
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
                        _SocialCircle(icon: FontAwesomeIcons.google, onTap: _continueWithGoogle),
                        const SizedBox(width: 16),
                        _SocialCircle(icon: FontAwesomeIcons.apple, onTap: _continueWithApple),
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
/*  HOME PAGE                                                                  */
/* ────────────────────────────────────────────────────────────────────────── */

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('EDUPRO Home')),
      body: u == null
          ? const Center(child: Text('No user'))
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: (u.photoURL != null) ? NetworkImage(u.photoURL!) : null,
                child: (u.photoURL == null) ? const Icon(Icons.person, size: 28) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('users').doc(u.uid).snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final fullName = data?['fullName'] ?? u.displayName ?? 'Unnamed';
                    final email = u.email ?? '(no email)';
                    final providers =
                    u.providerData.map((p) => p.providerId).join(', ');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(email),
                        Text('Providers: $providers'),
                      ],
                    );
                  },
                ),
              ),
            ]),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              onPressed: () async {
                if (!kIsWeb) {
                  try {
                    await gsi.GoogleSignIn().signOut();
                  } catch (_) {}
                }
                await _auth.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
                }
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
