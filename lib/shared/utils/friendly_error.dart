import '../services/api_exception.dart';

/// Turns anything a repository can throw into a sentence a person can act
/// on — never raw JSON, never a stack trace. The server's own `error`
/// strings are already written for people (plan limits, role blocks,
/// subscription messages), so they pass through; only the cases where the
/// server has nothing useful to say are replaced.
String friendlyError(Object error) {
  if (error is NetworkException) {
    return "Can't reach Aimify right now. Check your internet connection and try again.";
  }
  if (error is ApiException) {
    if (error.isRateLimited) return 'Too many attempts. Try again in a few minutes.';
    if (error.isUnauthorized) return 'Your session ended. Please sign in again.';
    if (error.code == 'storage_unavailable') {
      return 'Image storage is not available right now. Try again later.';
    }
    if (error.statusCode == 413) return 'That file is too large.';
    if (error.statusCode >= 500) {
      return 'Aimify had a problem on its side. Please try again in a moment.';
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
