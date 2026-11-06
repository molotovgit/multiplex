/// A snapshot of how busy a server is, read from Linux's /proc files.
class ServerStats {
  const ServerStats({
    required this.cpuPercent,
    required this.memUsedKb,
    required this.memTotalKb,
    required this.diskUsedKb,
    required this.diskTotalKb,
    required this.load,
    required this.uptime,
  });

  /// Share of CPU time spent working over about one second, 0 to 100.
  /// Null when the server's numbers could not be read.
  final double? cpuPercent;
  final int memUsedKb;
  final int memTotalKb;

  /// Disk space on "/", in KiB.
  final int diskUsedKb;
  final int diskTotalKb;

  /// The 1, 5 and 15 minute load averages, or empty when unknown.
  final List<double> load;
  final Duration? uptime;

  double? get memFraction => memTotalKb > 0 ? (memUsedKb / memTotalKb).clamp(0.0, 1.0) : null;
  double? get diskFraction => diskTotalKb > 0 ? (diskUsedKb / diskTotalKb).clamp(0.0, 1.0) : null;

  /// One command for `sh` that prints everything [parse] reads. It reads
  /// the CPU counters twice, a second apart, to see how busy the CPU is
  /// right now. On a system without Linux's /proc it prints "unsupported".
  /// Wrapped in `sh -c` so it works whatever the user's login shell is.
  static const command =
      "sh -c '"
      'if [ -r /proc/stat ] && [ -r /proc/meminfo ]; then '
      'head -n 1 /proc/stat; sleep 1; head -n 1 /proc/stat; '
      'grep -E "^(MemTotal|MemAvailable|MemFree|Buffers|Cached):" /proc/meminfo; '
      r'echo "load $(cat /proc/loadavg 2>/dev/null)"; '
      r'echo "uptime $(cat /proc/uptime 2>/dev/null)"; '
      r'echo "disk $(df -Pk / 2>/dev/null | tail -n 1)"; '
      'else echo unsupported; fi'
      "'";

  /// Reads the output of [command]. Null when the server is not Linux (or
  /// gave nothing usable).
  static ServerStats? parse(String output) {
    final lines = output.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty || lines.contains('unsupported')) return null;
    final cpu = lines.where((l) => l.startsWith('cpu ')).toList();
    final mem = <String, int>{};
    for (final line in lines) {
      final m = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line);
      if (m != null) mem[m.group(1)!] = int.parse(m.group(2)!);
    }
    final total = mem['MemTotal'];
    if (total == null) return null;
    final available = mem['MemAvailable'] ?? ((mem['MemFree'] ?? 0) + (mem['Buffers'] ?? 0) + (mem['Cached'] ?? 0));
    final (diskUsed, diskTotal) = _disk(_after(lines, 'disk '));
    return ServerStats(
      cpuPercent: cpu.length >= 2 ? _cpuBusy(cpu[0], cpu[1]) : null,
      memUsedKb: (total - available).clamp(0, total),
      memTotalKb: total,
      diskUsedKb: diskUsed,
      diskTotalKb: diskTotal,
      load: _load(_after(lines, 'load ')),
      uptime: _uptime(_after(lines, 'uptime ')),
    );
  }

  static String _after(List<String> lines, String prefix) => lines.where((l) => l.startsWith(prefix)).firstOrNull?.substring(prefix.length).trim() ?? '';

  /// The CPU line counts time in user, nice, system, idle, iowait, irq,
  /// softirq and steal. Idle and iowait are the time it was not working.
  static double? _cpuBusy(String first, String second) {
    List<int>? fields(String line) {
      final parts = line.split(RegExp(r'\s+')).skip(1).take(8).map(int.tryParse).toList();
      return parts.length < 4 || parts.contains(null) ? null : parts.cast<int>();
    }

    final a = fields(first), b = fields(second);
    if (a == null || b == null || a.length != b.length) return null;
    int idle(List<int> f) => f[3] + (f.length > 4 ? f[4] : 0);
    int sum(List<int> f) => f.fold(0, (x, y) => x + y);
    final total = sum(b) - sum(a);
    if (total <= 0) return null;
    return ((total - (idle(b) - idle(a))) * 100 / total).clamp(0.0, 100.0);
  }

  /// `df -Pk` line: filesystem, size, used, available, capacity, mount.
  static (int, int) _disk(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 6) return (0, 0);
    // The filesystem name may hold spaces, so count from the end.
    final n = parts.length;
    final total = int.tryParse(parts[n - 5]) ?? 0;
    final used = int.tryParse(parts[n - 4]) ?? 0;
    return (used, total);
  }

  static List<double> _load(String text) {
    final parts = text.split(RegExp(r'\s+')).take(3).map(double.tryParse).toList();
    return parts.length == 3 && !parts.contains(null) ? parts.cast<double>() : const [];
  }

  static Duration? _uptime(String text) {
    final seconds = double.tryParse(text.split(RegExp(r'\s+')).first);
    return seconds == null ? null : Duration(seconds: seconds.floor());
  }
}

/// Short, readable numbers for the status card.
abstract final class StatsFormat {
  /// "512 MB", "3.8 GB", "1.2 TB" from KiB.
  static String kib(int kib) {
    const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
    var value = kib.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  /// "5 min", "3 h 12 min", "12 days 4 h".
  static String uptime(Duration d) {
    if (d.inDays > 0) return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ${d.inHours % 24} h';
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    return '${d.inMinutes} min';
  }

  static String load(List<double> load) => load.map((l) => l.toStringAsFixed(2)).join('  ');
}
