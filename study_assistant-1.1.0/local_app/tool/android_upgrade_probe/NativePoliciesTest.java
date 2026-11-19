package journal.qa;

import com.example.studyassistant.BrowserPolicy;
import java.util.*;
import org.json.*;

/** JVM-only synthetic contract tests; no Android device or real credential access. */
public final class NativePoliciesTest {
  static int checks = 0;
  interface Checked { void run() throws Exception; }
  static void rejects(String label, Checked action) throws Exception {
    try { action.run(); } catch (AssertionError expected) { checks++; return; }
    throw new AssertionError("Accepted corrupted fixture: " + label);
  }
  public static void main(String[] args) throws Exception {
    String signed = "https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?workId=3&enc=a%2Bb%3D&x=1&x=2";
    String wrapped = com.example.studyassistant.ChaoxingAssignmentLink.build(signed);
    if (!wrapped.startsWith("chaoxingshareback://xuexitong.com?sharebacktype=1&url=")) throw new AssertionError("Wrong app scheme");
    String encoded = new java.net.URI(wrapped).getRawQuery().split("url=", 2)[1].split("&title=", 2)[0];
    if (!java.net.URLDecoder.decode(encoded, "UTF-8").equals(signed)) throw new AssertionError("Signed URL changed");
    checks += 2;
    for (String path : new String[]{
        "/page/renwuNew/stu/taskDetailStuForAnswer_new",
        "/page/renwuNew/stu/taskDetailStuAndAnsDetail_new",
        "/page/renwu/stu/taskDetailStuForAnswer",
        "/page/renwu/stu/taskDetailStuAndAnsDetail",
        "/page/renwuNew/notGroup/taskDetailStuForAnswerNotGroup_new",
        "/page/renwuNew/notGroup/taskDetailStuAndAnsDetailNotGroup_new",
        "/page/renwu/notGroup/taskDetailStuForAnswerNotGroup",
        "/page/renwu/notGroup/taskDetailStuAndAnsDetailNotGroup",
        "/page/quiz/stu/answerQuestion2"}) {
      String task = "https://mobilelearn.chaoxing.com" + path +
          "?courseId=7&classId=11&activeId=35&fid=0&enc=synthetic%2Bsignature";
      String link = com.example.studyassistant.ChaoxingAssignmentLink.build(task);
      if (link == null) throw new AssertionError("Classroom task rejected: " + path);
      String raw = new java.net.URI(link).getRawQuery().split("url=", 2)[1].split("&title=", 2)[0];
      if (!java.net.URLDecoder.decode(raw, "UTF-8").equals(task)) throw new AssertionError("Task URL changed");
      checks++;
    }
    String classroom = "https://mobilelearn.chaoxing.com/page/quiz/stu/answerQuestion2?courseId=7&classId=11&activeId=42";
    for (String bad : new String[]{classroom.replace("&activeId=42", ""),
        classroom + "&activeId=other", classroom + "&clazzId=other",
        classroom.replace("courseId=7", "courseId="),
        classroom.replace("mobilelearn.chaoxing.com", "evil.example"),
        classroom.replace("/page/quiz/stu/answerQuestion2", "/widget/pcpick/stu/index")}) {
      if (com.example.studyassistant.ChaoxingAssignmentLink.build(bad) != null) throw new AssertionError("Unsafe classroom URI accepted");
      checks++;
    }
    for (String bad : new String[]{"https://evil.example/work/task?workId=3", "https://chaoxing.com.evil.example/work/task?workId=3", "https://chaoxing.com/login", signed + "#fragment", signed.replace("https:", "http:")}) {
      if (com.example.studyassistant.ChaoxingAssignmentLink.build(bad) != null) throw new AssertionError("Unsafe app URI");
      checks++;
    }
    Set<String> selected = BrowserPolicy.browserPackages(Arrays.asList("browser.one", "browser.two", "browser.unavailable"),
      Arrays.asList("chaoxing.app", "browser.one", "browser.two", "browser.one"));
    if (!selected.equals(new LinkedHashSet<>(Arrays.asList("browser.one", "browser.two")))) throw new AssertionError("Browser selection accepted app-link handlers or unavailable browsers");
    checks++;
    if (!BrowserPolicy.browserPackages(Collections.emptyList(), Arrays.asList("chaoxing.app")).isEmpty()) throw new AssertionError("Missing browser must fail");
    checks++;
    for (String bad : new String[]{"http://mooc1.chaoxing.com/", "javascript:alert(1)",
      "https://user@mooc1.chaoxing.com/", "https://mooc1.chaoxing.com:8443/", "https:///missing", "https://bad host/"}) {
      if (BrowserPolicy.isAllowed(bad)) throw new AssertionError("Accepted invalid browser URL");
      checks++;
    }
    if (!BrowserPolicy.isAllowed("https://mooc1.chaoxing.com/work?id=synthetic") ||
        !BrowserPolicy.isAllowed("https://example.invalid:443/")) throw new AssertionError("HTTPS rejected");
    checks++;
    Map<String,String> credentials = UpgradeFixture.credentials(true);
    JSONObject valid = UpgradeFixture.expectedJournal(true);
    UpgradeFixture.verify(credentials, valid, Arrays.asList("60", "10"),
      Arrays.asList("fixture-unfollowed:fixture-class"), false, "both");
    checks++;
    for (String key : new String[]{"chaoxingAccount", "chaoxingPassword", "chaoxingDisplayName", "chaoxingAvatarUrl"}) {
      Map<String,String> altered = new HashMap<>(credentials); altered.put(key, "corrupted");
      rejects(key, () -> UpgradeFixture.verify(altered, valid, Arrays.asList("60", "10"), Arrays.asList("fixture-unfollowed:fixture-class"), false, "both"));
    }
    for (String field : new String[]{"id", "title", "courseName", "deadlineAt", "requirementsText", "status", "lastSyncedAt", "source", "submitUrl", "deadlineTrusted", "completedAt"}) {
      JSONObject altered = new JSONObject(valid.toString());
      altered.getJSONArray("records").getJSONObject(0).put(field, field.equals("deadlineTrusted") ? false : "corrupted");
      rejects(field, () -> UpgradeFixture.verify(credentials, altered, Arrays.asList("60", "10"), Arrays.asList("fixture-unfollowed:fixture-class"), false, "both"));
    }
    JSONObject hidden = new JSONObject(valid.toString()); hidden.put("hidden",new JSONArray());
    rejects("hidden", () -> UpgradeFixture.verify(credentials, hidden, Arrays.asList("60", "10"), Arrays.asList("fixture-unfollowed:fixture-class"), false, "both"));
    rejects("follow", () -> UpgradeFixture.verify(credentials, valid, Arrays.asList("60", "10"), Collections.emptyList(), false, "both"));
    rejects("reminder", () -> UpgradeFixture.verify(credentials, valid, Arrays.asList("60"), Arrays.asList("fixture-unfollowed:fixture-class"), false, "both"));
    rejects("legacy", () -> UpgradeFixture.verify(credentials, valid, Arrays.asList("60", "10"), Arrays.asList("fixture-unfollowed:fixture-class"), true, "both"));
    Map<String,String> retired = new HashMap<>(credentials); retired.put("shuniZuilingPassword","SAMPLE");
    rejects("retired", () -> UpgradeFixture.verify(retired, valid, Arrays.asList("60", "10"), Arrays.asList("fixture-unfollowed:fixture-class"), false, "both"));
    UpgradeFixture.verify(Collections.emptyMap(), UpgradeFixture.expectedJournal(false), Arrays.asList("60", "10"),
      Arrays.asList("fixture-unfollowed:fixture-class"), false, "retired");
    checks++;
    System.out.println("PASS " + checks + " native policy/upgrade fixture checks (synthetic JVM only)");
  }
}
