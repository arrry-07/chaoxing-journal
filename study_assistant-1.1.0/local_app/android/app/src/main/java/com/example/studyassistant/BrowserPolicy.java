package com.example.studyassistant;

import java.net.URI;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/** Input boundary for browser-only HTTPS navigation; never handles credentials. */
public final class BrowserPolicy {
    private static final Pattern STRICT_HOST = Pattern.compile(
        "^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
    );

    private BrowserPolicy() {}

    /** Require both an explicit browser registration and an HTTPS handler. */
    public static Set<String> browserPackages(Collection<String> registeredBrowsers, Collection<String> httpsHandlers) {
        Set<String> selected = new LinkedHashSet<>(httpsHandlers);
        selected.retainAll(registeredBrowsers);
        return selected;
    }

    private static URI parseStrictUri(String url) {
        if (url == null || url.isEmpty() || url.indexOf('\\') >= 0) return null;
        try {
            URI uri = new URI(url);
            String authority = uri.getRawAuthority();
            String host = uri.getHost();
            if (authority == null || authority.isEmpty() ||
                authority.indexOf('@') >= 0 || authority.indexOf('\\') >= 0) {
                return null;
            }
            if (uri.getRawUserInfo() != null || host == null || !STRICT_HOST.matcher(host).matches()) {
                return null;
            }
            return uri;
        } catch (Exception invalid) {
            return null;
        }
    }

    private static boolean isChaoxingHost(String host) {
        String lower = host.toLowerCase(Locale.ROOT);
        return "chaoxing.com".equals(lower) || lower.endsWith(".chaoxing.com");
    }

    public static boolean isAllowed(String url) {
        URI uri = parseStrictUri(url);
        return uri != null &&
            "https".equals(uri.getScheme()) &&
            (uri.getPort() == -1 || uri.getPort() == 443);
    }

    /** Strict HTTPS allowlist for first-party Chaoxing verification pages. */
    public static boolean isTrustedChaoxingUrl(String url) {
        URI uri = parseStrictUri(url);
        return uri != null &&
            "https".equals(uri.getScheme()) &&
            (uri.getPort() == -1 || uri.getPort() == 443) &&
            isChaoxingHost(uri.getHost());
    }

    /** Canonical origin ("https://host/") for a validated first-party Chaoxing URL. */
    public static String trustedChaoxingOrigin(String url) {
        if (!isTrustedChaoxingUrl(url)) return null;
        URI uri = parseStrictUri(url);
        if (uri == null) return null;
        return "https://" + uri.getHost().toLowerCase(Locale.ROOT) + "/";
    }

    /** Validated first-party Chaoxing URL without query or fragment for cookie export. */
    public static String trustedChaoxingPageOrigin(String url) {
        if (!isTrustedChaoxingUrl(url)) return null;
        URI uri = parseStrictUri(url);
        if (uri == null) return null;
        String rawPath = uri.getRawPath();
        return "https://" + uri.getHost().toLowerCase(Locale.ROOT) + (rawPath == null ? "" : rawPath);
    }

    /**
     * Upgrades a strict first-party Chaoxing HTTP URL (default/80 port, no userinfo,
     * no backslash authority confusion) to HTTPS; returns null for any other URL.
     */
    public static String upgradeChaoxingHttpUrl(String url) {
        URI uri = parseStrictUri(url);
        if (uri == null ||
            !"http".equals(uri.getScheme()) ||
            (uri.getPort() != -1 && uri.getPort() != 80) ||
            !isChaoxingHost(uri.getHost())) {
            return null;
        }
        StringBuilder upgraded = new StringBuilder("https://")
            .append(uri.getHost().toLowerCase(Locale.ROOT));
        if (uri.getRawPath() != null) upgraded.append(uri.getRawPath());
        if (uri.getRawQuery() != null) upgraded.append('?').append(uri.getRawQuery());
        if (uri.getRawFragment() != null) upgraded.append('#').append(uri.getRawFragment());
        String candidate = upgraded.toString();
        return isTrustedChaoxingUrl(candidate) ? candidate : null;
    }
}
