import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/otp_account.dart';
import '../../data/totp.dart';
import '../common/widgets.dart';

/// The clock codes are made from; tests pass a fixed one.
typedef CodeClock = DateTime Function();

/// Redraws its [builder] every second with the time, so codes and their
/// countdown stay current.
class CodeTicker extends StatefulWidget {
  const CodeTicker({super.key, required this.builder, this.clock});

  final Widget Function(BuildContext context, DateTime now) builder;
  final CodeClock? clock;

  @override
  State<CodeTicker> createState() => _CodeTickerState();
}

class _CodeTickerState extends State<CodeTicker> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, (widget.clock ?? DateTime.now)());
}

/// A ring that empties as the code's time runs out, with the seconds left
/// in the middle. Turns the warning colour in the last five seconds.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.secondsLeft, required this.period, this.size = 36});

  final int secondsLeft;
  final int period;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsTheme.of(context);
    final ending = secondsLeft <= 5;
    return Semantics(
      label: '$secondsLeft seconds left',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: secondsLeft / period,
                strokeWidth: 3,
                color: ending ? colors.danger : colors.accent,
                backgroundColor: colors.outline,
              ),
            ),
            Text('$secondsLeft', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ending ? colors.danger : colors.muted)),
          ],
        ),
      ),
    );
  }
}

/// A code in large terminal-font digits, split in two halves.
class CodeText extends StatelessWidget {
  const CodeText(this.code, {super.key, this.style});

  final String code;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.headlineSmall;
    return MonoText(Totp.grouped(code), style: base?.copyWith(letterSpacing: 1.5));
  }
}

/// The current code of [account], or null when its secret is broken (it
/// was checked when saved, so only a damaged vault gets here).
String? currentCode(OtpAccount account, DateTime now) {
  try {
    return Totp.now(account, now);
  } on FormatException {
    return null;
  }
}
