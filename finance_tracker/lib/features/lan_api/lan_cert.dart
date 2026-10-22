/// Self-signed TLS identity for the LAN API (contract: `docs/API.md` §3).
///
/// On first LAN start: generate RSA-2048 + self-signed cert
/// (CN=`finance-tracker.local`, O=`Personal Finance Tracker`, 10-year
/// validity), persist PEM (key+cert) in the app documents dir, reuse after.
///
/// Pure-Dart deps, split by what each can actually do on the Dart VM:
/// - `crypto_keys` (ships with `x509`): RSA-2048 keygen + PKCS#1-v1.5/SHA-256
///   TBS signing. (package:cryptography's RSA keygen/sign is WebCrypto-only
///   and throws UnimplementedError on the VM.)
/// - `cryptography`: CSRNG serial via `SecretKeyData.random`.
/// - `x509`: cert model + PEM parsing for parse-back verification.
/// - DER encoding is hand-rolled below because x509 0.2.4's OID *encoder*
///   (`ObjectIdentifier.toAsn1`) passes DER content bytes to an asn1lib
///   constructor that expects OID components, emitting garbage algorithm
///   OIDs with asn1lib 1.x (BoringSSL rejects the cert with
///   UNSUPPORTED_ALGORITHM). The x509 *parser* is correct and is used to
///   verify our bytes parse back with the expected subject/validity.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:path_provider/path_provider.dart';
import 'package:x509/x509.dart' as x509;

const String lanCertCommonName = 'finance-tracker.local';
const String lanCertOrganization = 'Personal Finance Tracker';

const String _keyFileName = 'lan_api_key.pem';
const String _certFileName = 'lan_api_cert.pem';

/// Big-endian bytes → positive BigInt.
BigInt _bytesToBigInt(List<int> bytes) => bytes.fold<BigInt>(
  BigInt.zero,
  (a, b) => a * BigInt.from(256) + BigInt.from(b),
);

/// Positive BigInt → minimal big-endian bytes.
Uint8List _bigIntToBytes(BigInt v) {
  if (v == BigInt.zero) return Uint8List.fromList(const <int>[0]);
  var n = v;
  final out = <int>[];
  while (n > BigInt.zero) {
    out.add((n & BigInt.from(0xff)).toInt());
    n = n >> 8;
  }
  return Uint8List.fromList(out.reversed.toList());
}

// -- minimal DER writers --

List<int> _derLength(int n) {
  if (n < 128) return <int>[n];
  final bytes = _bigIntToBytes(BigInt.from(n));
  return <int>[0x80 | bytes.length, ...bytes];
}

List<int> _derInteger(BigInt v) {
  var body = _bigIntToBytes(v);
  if (body[0] & 0x80 != 0) body = Uint8List.fromList(<int>[0, ...body]);
  return <int>[0x02, ..._derLength(body.length), ...body];
}

List<int> _derSequence(List<List<int>> parts) {
  final body = parts.expand((p) => p).toList();
  return <int>[0x30, ..._derLength(body.length), ...body];
}

List<int> _derSet(List<List<int>> parts) {
  final body = parts.expand((p) => p).toList();
  return <int>[0x31, ..._derLength(body.length), ...body];
}

/// Correct base-128 OID encoding from arc nodes (the x509 0.2.4 encoder
/// gets this wrong with asn1lib 1.x — hence this file).
List<int> _derOid(List<int> nodes) {
  final body = <int>[nodes[0] * 40 + nodes[1]];
  for (final v in nodes.skip(2)) {
    var n = v;
    var stack = <int>[n & 0x7f];
    n >>= 7;
    while (n > 0) {
      stack.add((n & 0x7f) | 0x80);
      n >>= 7;
    }
    body.addAll(stack.reversed);
  }
  return <int>[0x06, ..._derLength(body.length), ...body];
}

List<int> _derNull() => const <int>[0x05, 0x00];

List<int> _derBitString(List<int> content) => <int>[
  0x03,
  ..._derLength(content.length + 1),
  0x00, // unused bits
  ...content,
];

List<int> _derPrintableString(String s) {
  final bytes = ascii.encode(s);
  return <int>[0x13, ..._derLength(bytes.length), ...bytes];
}

List<int> _derUtcTime(DateTime utc) {
  // UTCTime YYMMDDHHMMSSZ; valid for years 1950–2049 (we use now → +10y).
  String two(int n) => n.toString().padLeft(2, '0');
  final s =
      '${two(utc.year % 100)}${two(utc.month)}${two(utc.day)}'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  final bytes = ascii.encode(s);
  return <int>[0x17, ..._derLength(bytes.length), ...bytes];
}

/// [0] EXPLICIT wrapper (certificate version).
List<int> _derExplicit0(List<int> inner) =>
    <int>[0xa0, ..._derLength(inner.length), ...inner];

String _pem(List<int> der, String type) {
  final buf = StringBuffer()..writeln('-----BEGIN $type-----');
  final b64 = base64.encode(der);
  for (var i = 0; i < b64.length; i += 64) {
    buf.writeln(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  buf.writeln('-----END $type-----');
  return buf.toString();
}

/// Generates a fresh (keyPem, certPem) identity. Record fields: `$1` key,
/// `$2` cert. RSA-2048 via `crypto_keys`; serial via `cryptography` CSRNG.
Future<(String, String)> generateLanIdentity() async {
  final pair = x509.KeyPair.generateRsa(bitStrength: 2048);
  final priv = pair.privateKey! as x509.RsaPrivateKey;
  final pub = pair.publicKey! as x509.RsaPublicKey;

  // 64-bit positive serial from the cryptography CSRNG (RFC 5280: unique+).
  final serialBytes = await crypto.SecretKeyData.random(
    length: 8,
  ).extractBytes();
  var serial = _bytesToBigInt(serialBytes);
  serial = serial & ((BigInt.one << 63) - BigInt.one);
  if (serial == BigInt.zero) serial = BigInt.one;

  const cnOid = [2, 5, 4, 3]; // commonName
  const oOid = [2, 5, 4, 10]; // organizationName
  const rsaOid = [1, 2, 840, 113549, 1, 1, 1]; // rsaEncryption
  const sigOid = [1, 2, 840, 113549, 1, 1, 11]; // sha256WithRSAEncryption

  final sigAlg = _derSequence([_derOid(sigOid), _derNull()]);
  final name = _derSequence([
    _derSet([
      _derSequence([_derOid(cnOid), _derPrintableString(lanCertCommonName)]),
    ]),
    _derSet([
      _derSequence([_derOid(oOid), _derPrintableString(lanCertOrganization)]),
    ]),
  ]);
  final now = DateTime.now().toUtc();
  final validity = _derSequence([
    _derUtcTime(now),
    _derUtcTime(now.add(const Duration(days: 3650))), // ~10 years
  ]);
  final spki = _derSequence([
    _derSequence([_derOid(rsaOid), _derNull()]),
    _derBitString(
      _derSequence([_derInteger(pub.modulus), _derInteger(pub.exponent)]),
    ),
  ]);
  final tbsDer = _derSequence([
    _derExplicit0(_derInteger(BigInt.from(2))), // v3
    _derInteger(serial),
    sigAlg,
    name, // issuer
    validity,
    name, // subject (self-signed)
    spki,
  ]);
  final sig = pair
      .createSigner(x509.algorithms.signing.rsa.sha256)
      .sign(tbsDer);
  final certDer = _derSequence([tbsDer, sigAlg, _derBitString(sig.data)]);

  // PKCS#1 RSAPrivateKey DER (version, n, e, d, p, q, dp, dq, qinv).
  final one = BigInt.one;
  final pSub1 = priv.firstPrimeFactor - one;
  final qSub1 = priv.secondPrimeFactor - one;
  final keyDer = _derSequence([
    _derInteger(BigInt.zero),
    _derInteger(priv.modulus),
    _derInteger(pub.exponent),
    _derInteger(priv.privateExponent),
    _derInteger(priv.firstPrimeFactor),
    _derInteger(priv.secondPrimeFactor),
    _derInteger(priv.privateExponent.remainder(pSub1)),
    _derInteger(priv.privateExponent.remainder(qSub1)),
    _derInteger(priv.secondPrimeFactor.modInverse(priv.firstPrimeFactor)),
  ]);

  return (
    _pem(keyDer, 'RSA PRIVATE KEY'),
    _pem(certDer, 'CERTIFICATE'),
  );
}

/// Parses [certPem] back with the x509 parser and returns the subject string.
/// Throws on garbage — used by tests to prove our DER is well-formed.
String lanCertSubject(String certPem) {
  for (final obj in x509.parsePem(certPem)) {
    if (obj is x509.X509Certificate) return '${obj.tbsCertificate.subject}';
  }
  throw const FormatException('No certificate in PEM');
}

/// Loads the persisted TLS identity (generating it on first use) and returns
/// a [SecurityContext] the server binds with. Pass [directory] in tests to
/// avoid touching the real app documents dir.
Future<SecurityContext> loadOrCreateLanSecurityContext({
  Directory? directory,
}) async {
  final dir = directory ?? await getApplicationDocumentsDirectory();
  final keyFile = File('${dir.path}/$_keyFileName');
  final certFile = File('${dir.path}/$_certFileName');

  Future<SecurityContext> contextFrom(String keyPem, String certPem) async {
    final ctx = SecurityContext();
    ctx.useCertificateChainBytes(utf8.encode(certPem));
    ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    return ctx;
  }

  if (await keyFile.exists() && await certFile.exists()) {
    try {
      return await contextFrom(
        await keyFile.readAsString(),
        await certFile.readAsString(),
      );
    } catch (_) {
      // Corrupt PEMs: fall through and regenerate.
    }
  }
  final (keyPem, certPem) = await generateLanIdentity();
  await keyFile.writeAsString(keyPem, flush: true);
  await certFile.writeAsString(certPem, flush: true);
  return contextFrom(keyPem, certPem);
}
