package com.example.studyassistant;

import java.net.URI;
import java.net.URLEncoder;

/** Verified on Chaoxing 7.0.6: public share-back opens its own viewer. */
public final class ChaoxingAssignmentLink {
    private ChaoxingAssignmentLink() {}

    public static String build(String original) {
        if (!BrowserPolicy.isAllowed(original)) return null;
        try {
            URI uri = new URI(original);
            String host = uri.getHost();
            if (!(host.equals("chaoxing.com") || host.endsWith(".chaoxing.com")) ||
                uri.getRawFragment() != null || uri.getRawPath() == null ||
                !uri.getRawPath().matches("^/(?:mooc-ans/(?:mooc2/)?|mooc2/|mooc2-ans/)?work/[a-zA-Z0-9_.-]+$")) return null;
            // Encode the complete original once; the receiving app decodes the
            // outer query once. Rebuilding the inner signed URL breaks enc.
            return "chaoxingshareback://xuexitong.com?sharebacktype=1&url=" +
                URLEncoder.encode(original, "UTF-8") + "&title=" +
                URLEncoder.encode("作业详情", "UTF-8");
        } catch (Exception invalid) {
            return null;
        }
    }
}
