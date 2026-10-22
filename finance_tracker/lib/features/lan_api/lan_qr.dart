/// QR connect payload — pure function, unit-tested (contract: docs/API.md §8).
///
/// The LAN screen renders [buildQrPayload] output as a QR; scanners get the
/// https base URL + token without typing.
library;

import 'dart:convert';

/// Builds the exact JSON string encoded in the LAN screen QR:
/// `{"url":"https://<ip>:8080/api/v1","token":"XXXXXX"}`.
String buildQrPayload(String baseApiUrl, String token) =>
    jsonEncode(<String, String>{'url': baseApiUrl, 'token': token});
