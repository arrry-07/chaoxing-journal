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

    if (uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        (uri.host.isNotEmpty && uri.host != 'assignments') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }

    final List<String> segments;
    try {
      segments = uri.pathSegments;
    } on FormatException {
      return null;
    }
    if (uri.host == 'assignments') {
      if (segments.isEmpty) {
        return '/assignments';
      }
      if (segments.length != 1 || !_safeId(segments.single)) {
        return null;
      }
      return assignmentLocation(segments.single);
    }

    if (segments.isEmpty) {
      return '/assignments';
    }

    if (segments.first != 'assignments') {
      return '/assignments';
    }

    if (segments.length == 1) {
      return '/assignments';
    }

    if (segments.length != 2 || !_safeId(segments[1])) {
      return null;
    }
    return assignmentLocation(segments[1]);
  }

  /// Only an internal assignment detail may survive an authentication redirect.
  static String? validatedAssignmentLocation(String? location) {
    final uri = Uri.tryParse(location ?? '');
    final List<String>? segments;
    try {
      segments = uri?.pathSegments;
    } on FormatException {
      return null;
    }
    if (uri == null ||
        segments == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/') ||
        segments.length != 2 ||
        segments.first != 'assignments' ||
        !_safeId(segments[1])) {
      return null;
    }
    return assignmentLocation(segments[1]);
  }

  static bool _safeId(String id) =>
      id.isNotEmpty &&
      id != '.' &&
      id != '..' &&
      !RegExp(r'[\x00-\x20/\\?#%]').hasMatch(id);
}

String loginSuccessLocation(String? requestedTarget) =>
    AppDeepLinks.validatedAssignmentLocation(requestedTarget) ?? '/assignments';
