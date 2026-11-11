import 'dart:convert';

import 'package:crypto/crypto.dart';

class AccountIdentity {
  const AccountIdentity._();

  static String hash(String account) =>
      sha256.convert(utf8.encode(account.trim())).toString();
}
