package com.example.studyassistant;

import java.net.URI;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;

/** Input boundary for browser-only HTTPS navigation; never handles credentials. */
public final class BrowserPolicy {
    private BrowserPolicy() {}
    /** Require both an explicit browser registration and an HTTPS handler. */
    public static Set<String> browserPackages(Collection<String> registeredBrowsers, Collection<String> httpsHandlers) {
        Set<String> selected = new LinkedHashSet<>(httpsHandlers);
        selected.retainAll(registeredBrowsers);
        return selected;
    }
    public static boolean isAllowed(String url) {
        if (url == null || url.isEmpty()) return false;
        try {
            URI uri = new URI(url);
            return "https".equals(uri.getScheme()) && uri.getHost() != null &&
                !uri.getHost().isEmpty() && uri.getRawUserInfo() == null &&
                (uri.getPort() == -1 || uri.getPort() == 443);
        } catch (Exception invalid) {
            return false;
        }
    }
}
