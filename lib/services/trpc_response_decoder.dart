/// Converts the already-unwrapped tRPC `result.data.json` payload into the
/// map contract expected by mutation callers. The mobile tRPC client uses a
/// single POST, not batching, so an unexpected List is a contract error.
Map<String, dynamic> requireMapResponse(dynamic value, String procedure) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException(
    'Unexpected response shape from $procedure: expected object.',
  );
}
