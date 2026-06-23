// Backend connection config, supplied at build time via --dart-define so the
// cloud URL + secret token are never hardcoded in source.
//
// Local dev (defaults): connects to the local backend, no token.
//   flutter run -d macos
//
// Cloud build: pass the deployed wss URL + token.
//   flutter run -d macos \
//     --dart-define=MONAMI_WS_BASE=wss://<service>.run.app/ws/voice \
//     --dart-define=MONAMI_TOKEN=<the-secret-token>
//
// The token lives in Secret Manager + a gitignored local config — never commit it.

class AppConfig {
  /// WebSocket base URL (without the query string). Defaults to local dev.
  static const String wsBase = String.fromEnvironment(
    'MONAMI_WS_BASE',
    defaultValue: 'ws://127.0.0.1:8000/ws/voice',
  );

  /// Shared-secret token for the backend auth gate. Empty = local dev (no gate).
  static const String token = String.fromEnvironment('MONAMI_TOKEN');

  /// REST base = the ORIGIN of [wsBase]: ws→http, wss→https, path stripped.
  /// The REST endpoints (e.g. `/devices/{id}/children`) hang off the origin, NOT
  /// off the `/ws/voice` WS path — so we must drop the path, not just swap scheme.
  /// e.g. `wss://foo.run.app/ws/voice` → `https://foo.run.app`.
  static String get restBase => restBaseOf(wsBase);

  /// Pure helper (testable): origin of a ws/wss URL with the path removed.
  static String restBaseOf(String ws) {
    final uri = Uri.parse(ws);
    final scheme = switch (uri.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      final s => s, // already http(s) or unknown — leave as-is
    };
    // Rebuild origin only: scheme + authority (host[:port]); drop path/query.
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }
}
