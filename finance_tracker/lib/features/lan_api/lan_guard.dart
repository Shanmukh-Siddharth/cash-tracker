/// LAN subnet guard — pure functions, unit-testable.
///
/// Only import used is `dart:io` ([InternetAddress]); no Flutter, no repos.
library;

import 'dart:io' show InternetAddress, InternetAddressType;

/// True when [ip] parses as IPv4 inside a private range:
/// `10/8`, `172.16/12`, `192.168/16`.
///
/// Loopback (`127/8`), IPv6, and unparseable input return false
/// (IPv6 is skipped in v1 — guard rejects it).
bool isPrivateIp(String ip) {
  final addr = InternetAddress.tryParse(ip.trim());
  if (addr == null || addr.type != InternetAddressType.IPv4) return false;
  final b = addr.rawAddress;
  if (b.length != 4) return false;
  final a = b[0], c = b[1];
  if (a == 10) return true;
  if (a == 192 && c == 168) return true;
  if (a == 172 && c >= 16 && c <= 31) return true;
  return false;
}

/// True when both IPs parse as IPv4 and share the first three octets
/// (same /24: `ip & 255.255.255.0` equal).
///
/// IPv6 or unparseable input returns false (skipped in v1).
bool isSameLan(String serverIp, String clientIp) {
  final server = InternetAddress.tryParse(serverIp.trim());
  final client = InternetAddress.tryParse(clientIp.trim());
  if (server == null || client == null) return false;
  if (server.type != InternetAddressType.IPv4 ||
      client.type != InternetAddressType.IPv4) {
    return false;
  }
  final sb = server.rawAddress;
  final cb = client.rawAddress;
  if (sb.length != 4 || cb.length != 4) return false;
  return sb[0] == cb[0] && sb[1] == cb[1] && sb[2] == cb[2];
}
