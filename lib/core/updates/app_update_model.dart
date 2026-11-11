class InstalledApp {
  const InstalledApp(this.version, this.code, this.package);
  final String version, package;
  final int code;
}

class AppUpdate {
  AppUpdate({
    required this.version,
    required this.code,
    required this.minimum,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
    required this.package,
  });
  final String version, url, sha256, notes, package;
  final int code, minimum, size;
  bool newerThan(int installed) => code > installed;
  bool mandatoryFor(int installed) =>
      newerThan(installed) && installed < minimum;
  factory AppUpdate.parse(Map<String, dynamic> json) {
    int number(String key) {
      final n = json[key];
      if (n is! int || n < 0) {
        throw const FormatException('Metadata angka pembaruan tidak valid');
      }
      return n;
    }

    final code = number('latest_version_code'),
        minimum = number('minimum_supported_version_code'),
        size = number('file_size');
    if (code > 2100000000 || minimum > code || size > 512 * 1024 * 1024) {
      throw const FormatException('Batas metadata pembaruan tidak valid');
    }
    final hash = '${json['sha256'] ?? ''}'.toLowerCase();
    if (code > 0 && (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) || size == 0)) {
      throw const FormatException('Integritas rilis belum tersedia');
    }
    return AppUpdate(
      version: '${json['latest_version'] ?? ''}',
      code: code,
      minimum: minimum,
      url: '${json['download_url'] ?? ''}',
      sha256: hash,
      size: size,
      notes: '${json['changelog'] ?? ''}',
      package: '${json['package_name'] ?? ''}',
    );
  }
  Map<String, dynamic> toJson() => {
    'latest_version': version,
    'latest_version_code': code,
    'minimum_supported_version_code': minimum,
    'download_url': url,
    'sha256': sha256,
    'file_size': size,
    'changelog': notes,
    'package_name': package,
  };
}
