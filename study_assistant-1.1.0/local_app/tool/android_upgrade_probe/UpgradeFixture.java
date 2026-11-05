package journal.qa;

import java.time.Instant;
import java.util.*;
import org.json.*;

/** Fixed synthetic upgrade contract shared by the instrument and its JVM tests. */
public final class UpgradeFixture {
  private UpgradeFixture() {}
  static final String SYNC = "2026-11-04T00:00:00.000Z";
  static final String[] TITLES = {"函数极限与连续：习题整理", "阅读报告：把晚霞借给你", "程序设计综合实验报告与项目复盘", "预习下一章，整理想问的问题"};
  static final String[] COURSES = {"高等数学", "大学语文", "程序设计", "大学英语"};
  static final String[] DATES = {"2026-11-04T10:00:00.000Z", "2026-11-04T12:30:00.000Z", "2026-11-04T14:00:00.000Z", "2026-11-05T10:00:00.000Z"};
  static final String[] STATUS = {"pending", "returned", "submitted", "completed"};
  static String id(int i) { return "cx:work:fixture-course:fixture-class:" + i; }
  public static Map<String,String> credentials(boolean cx) {
    Map<String,String> result = new HashMap<>();
    if (cx) {
      result.put("chaoxingAccount", "journal-demo-student");
      result.put("chaoxingPassword", "SAMPLE_NOT_A_REAL_PASSWORD");
      result.put("chaoxingDisplayName", "手帐同学 · 示例数据");
      result.put("chaoxingAvatarUrl", "https://example.invalid/fixture-avatar.png");
    }
    return result;
  }
  public static JSONObject record(int i) throws JSONException {
    return new JSONObject().put("id", id(i)).put("title", TITLES[i]).put("courseName", COURSES[i])
      .put("deadlineAt", DATES[i]).put("status", STATUS[i]).put("source", "courseWork")
      .put("deadlineTrusted", true).put("requirementsText", "示例数据，仅用于本机升级验收")
      .put("lastSyncedAt", SYNC).put("completedAt", i == 3 ? "2026-11-04T01:00:00.000Z" : JSONObject.NULL)
      .put("submitUrl", "https://mooc1.chaoxing.com/work/fixture?courseId=fixture-course&classId=fixture-class&workId=" + i);
  }
  public static JSONObject expectedJournal(boolean cx) throws JSONException {
    JSONArray records = new JSONArray(), hidden = new JSONArray();
    if (cx) {
      for (int i = 0; i < 4; i++) records.put(record(i));
      hidden.put(id(1)); hidden.put(id(3));
    }
    return new JSONObject().put("schemaVersion",1).put("records",records).put("hidden",hidden)
      .put("lastSync",cx ? SYNC : JSONObject.NULL);
  }
  static void equal(Object expected, Object actual, String field) {
    if (!Objects.equals(expected, actual)) throw new AssertionError("Upgrade fixture mismatch: " + field);
  }
  static void instant(Object expected, Object actual, String field) {
    if (expected == JSONObject.NULL) { equal(JSONObject.NULL, actual, field); return; }
    try { equal(Instant.parse(expected.toString()), Instant.parse(actual.toString()), field); }
    catch (RuntimeException error) { throw new AssertionError("Invalid upgrade instant: " + field); }
  }
  static List<String> strings(JSONArray array) throws JSONException {
    List<String> result = new ArrayList<>();
    for (int i = 0; i < array.length(); i++) result.add(array.getString(i));
    Collections.sort(result); return result;
  }
  public static void verify(Map<?,?> credentials, JSONObject journal, List<String> reminders,
      List<String> unfollowed, boolean hasLegacyKeys, String kind) throws JSONException {
    if (!Arrays.asList("both","chaoxing","retired").contains(kind)) throw new AssertionError("Unknown fixture kind");
    boolean cx = !kind.equals("retired");
    for (Object key : credentials.keySet()) if (key.toString().startsWith("shuni")) throw new AssertionError("Retired credential survived");
    equal(credentials(cx), credentials, "complete credentials");
    equal(1, journal.getInt("schemaVersion"), "schemaVersion");
    JSONArray records = journal.getJSONArray("records");
    equal(cx ? 4 : 0, records.length(), "record count");
    Map<String,JSONObject> indexed = new HashMap<>();
    for (int i = 0; i < records.length(); i++) {
      JSONObject value = records.getJSONObject(i);
      if (indexed.put(value.getString("id"), value) != null) throw new AssertionError("Duplicate record");
      if (value.getString("id").startsWith("snzl:")) throw new AssertionError("Retired record survived");
    }
    if (cx) for (int i = 0; i < 4; i++) {
      JSONObject expected = record(i), actual = indexed.get(id(i));
      if (actual == null) throw new AssertionError("Missing fixed record " + i);
      for (String field : Arrays.asList("id","title","courseName","status","source","requirementsText","submitUrl","deadlineTrusted")) {
        equal(expected.get(field),actual.get(field),field + "[" + i + "]");
      }
      for (String field : Arrays.asList("deadlineAt","lastSyncedAt","completedAt")) instant(expected.get(field),actual.get(field),field + "[" + i + "]");
      equal(false,actual.optBoolean("deadlineReadFailed",false),"deadlineReadFailed");
    }
    equal(strings(expectedJournal(cx).getJSONArray("hidden")),strings(journal.getJSONArray("hidden")),"hidden");
    instant(cx ? SYNC : JSONObject.NULL, journal.get("lastSync"), "lastSync");
    equal(Arrays.asList("60","10"),reminders,"reminders");
    equal(Arrays.asList("fixture-unfollowed:fixture-class"),unfollowed,"unfollowed courses");
    if (hasLegacyKeys) throw new AssertionError("Legacy journal key survived");
  }
}
