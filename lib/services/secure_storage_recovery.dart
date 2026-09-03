/// Centralizes recovery from Android Keystore/key-material mismatch after a
/// backup restores encrypted preferences onto a newly installed app.
///
/// The helper intentionally logs no exception or storage content. Callers
/// receive null after an expected decrypt failure and should show the clean
/// login flow rather than retrying the unreadable encrypted value.
bool isSecureStorageDecryptFailure(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('bad_decrypt') ||
      text.contains('decrypt') ||
      text.contains('invalidkey') ||
      text.contains('keystore') ||
      text.contains('key permanently invalidated');
}

Future<T?> readSecureValueOrRecover<T>({
  required Future<T?> Function() read,
  required Future<void> Function() wipeSession,
  required void Function(String event) log,
}) async {
  try {
    return await read();
  } catch (error) {
    if (!isSecureStorageDecryptFailure(error)) rethrow;
    log('Secure-storage recovery: unreadable encrypted session cleared.');
    await wipeSession();
    return null;
  }
}
