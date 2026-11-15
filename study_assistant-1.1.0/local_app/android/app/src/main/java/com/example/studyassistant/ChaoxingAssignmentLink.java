package com.example.studyassistant;

import java.net.URI;
import java.net.URLEncoder;
import java.net.URLDecoder;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Verified on Chaoxing 7.0.6: public share-back opens its own viewer. */
public final class ChaoxingAssignmentLink {
    private ChaoxingAssignmentLink() {}
    private static final List<String> CLASSROOM_PATHS = Arrays.asList(
        "/page/renwuNew/stu/taskDetailStuForAnswer_new",
        "/page/renwuNew/stu/taskDetailStuAndAnsDetail_new",
        "/page/renwu/stu/taskDetailStuForAnswer",
        "/page/renwu/stu/taskDetailStuAndAnsDetail",
        "/page/renwuNew/notGroup/taskDetailStuForAnswerNotGroup_new",
        "/page/renwuNew/notGroup/taskDetailStuAndAnsDetailNotGroup_new",
        "/page/renwu/notGroup/taskDetailStuForAnswerNotGroup",
        "/page/renwu/notGroup/taskDetailStuAndAnsDetailNotGroup",
        "/page/quiz/stu/answerQuestion2"
    );

    public static String build(String original) {
        if (!BrowserPolicy.isAllowed(original)) return null;
        try {
            URI uri = new URI(original);
            String host = uri.getHost();
            if (!(host.equals("chaoxing.com") || host.endsWith(".chaoxing.com")) ||
                uri.getRawFragment() != null || uri.getRawPath() == null) return null;
            boolean formal = uri.getRawPath().matches(
                "^/(?:mooc-ans/(?:mooc2/)?|mooc2/|mooc2-ans/)?work/[a-zA-Z0-9_.-]+$");
            boolean classroom = host.equals("mobilelearn.chaoxing.com") &&
                CLASSROOM_PATHS.contains(uri.getRawPath()) && hasClassroomIdentity(uri);
            boolean ai = host.equals("mooc2-ans.chaoxing.com") &&
                uri.getRawPath().equals("/ai-evaluate/v2/redirect/active/stu") && hasAiIdentity(uri);
            if (!formal && !classroom && !ai) return null;
            // Encode the complete original once; the receiving app decodes the
            // outer query once. Rebuilding the inner signed URL breaks enc.
            return "chaoxingshareback://xuexitong.com?sharebacktype=1&url=" +
                URLEncoder.encode(original, "UTF-8") + "&title=" +
                URLEncoder.encode("作业详情", "UTF-8");
        } catch (Exception invalid) {
            return null;
        }
    }

    private static boolean hasAiIdentity(URI uri) throws Exception {
        if (uri.getRawQuery() == null) return false;
        Map<String, String> values = new HashMap<>();
        for (String part : uri.getRawQuery().split("&")) {
            String[] pair = part.split("=", 2);
            String key = URLDecoder.decode(pair[0], "UTF-8").toLowerCase(Locale.ROOT);
            if (key.equals("classid") || key.equals("jclassid")) key = "clazzid";
            if (!key.equals("courseid") && !key.equals("clazzid") && !key.equals("publishuuid")) continue;
            String value = pair.length == 2 ? URLDecoder.decode(pair[1], "UTF-8") : "";
            if (value.trim().isEmpty() || (values.containsKey(key) && !values.get(key).equals(value))) return false;
            values.put(key, value);
        }
        return values.containsKey("courseid") && values.containsKey("clazzid") &&
            values.containsKey("publishuuid") && values.get("publishuuid").matches(
                "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
    }

    private static boolean hasClassroomIdentity(URI uri) throws Exception {
        if (uri.getRawQuery() == null) return false;
        Map<String, String> values = new HashMap<>();
        for (String part : uri.getRawQuery().split("&")) {
            String[] pair = part.split("=", 2);
            String key = URLDecoder.decode(pair[0], "UTF-8").toLowerCase(Locale.ROOT);
            if (key.equals("clazzid") || key.equals("jclassid")) key = "classid";
            if (!key.equals("courseid") && !key.equals("classid") && !key.equals("activeid")) continue;
            String value = pair.length == 2 ? URLDecoder.decode(pair[1], "UTF-8") : "";
            if (value.trim().isEmpty() || (values.containsKey(key) && !values.get(key).equals(value))) return false;
            values.put(key, value);
        }
        return values.containsKey("courseid") && values.containsKey("classid") && values.containsKey("activeid");
    }
}
