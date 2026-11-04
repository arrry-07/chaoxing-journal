class AppDeepLinks {
  static const scheme = 'studyassistant';

  static String assignmentUri(String assignmentId) {
    return '$scheme://${assignmentLocation(assignmentId)}';
  }

  static String assignmentLocation(String assignmentId) {
    return '/assignments/${Uri.encodeComponent(assignmentId)}';
  }

  static String? normalizeIncomingLocation(Uri uri) {
    if (uri.scheme != scheme) {
      return null;
    }

    if (uri.host == 'assignments') {
      if (uri.pathSegments.isEmpty) {
        return '/assignments';
      }
      return assignmentLocation(uri.pathSegments.join('/'));
    }

    if (uri.pathSegments.isEmpty) {
      return '/assignments';
    }

    if (uri.pathSegments.first != 'assignments') {
      return '/assignments';
    }

    if (uri.pathSegments.length == 1) {
      return '/assignments';
    }

    return assignmentLocation(uri.pathSegments.skip(1).join('/'));
  }
}
