/// The one login screen: a code and a nickname. A team code (`htf-…`) makes
/// you a player of that team; a judge code (`jdg-…`) needs no nickname and
/// makes you a judge. Pops with the [Session], or null for "play without
/// logging in".
library;

import 'package:flutter/material.dart';

import 'globe/palette.dart';
import 'session.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _code = TextEditingController();
  final _nick = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _judge => isJudgeCode(_code.text);

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.trim().isEmpty ||
        (!_judge && _nick.text.trim().isEmpty)) {
      setState(() => _error =
          _judge ? 'Type your judge code.' : 'Type your team code and a nickname.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await Session.login(_code.text, _nick.text);
      if (mounted) Navigator.of(context).pop(s);
    } on LoginError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message == 'unknown code'
              ? 'That code is not known. Check it with your coach.'
              : e.message;
        });
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _nick.dispose();
    super.dispose();
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(kCyan))),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(kBgVoid),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ACHRONA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 30,
                          letterSpacing: 8,
                          fontWeight: FontWeight.w300)),
                  const SizedBox(height: 8),
                  const Text('Log in with your team code',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    autocorrect: false,
                    style: const TextStyle(color: Colors.white),
                    decoration: _field('Code (htf-… or jdg-…)'),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _judge ? _submit() : null,
                  ),
                  if (!_judge) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nick,
                      maxLength: 24,
                      style: const TextStyle(color: Colors.white),
                      decoration: _field('Your nickname'),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Color(0xFFFF6B8A))),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(kCyan),
                        foregroundColor: const Color(kBgVoid),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ENTER', style: TextStyle(letterSpacing: 3)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('play without logging in',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
