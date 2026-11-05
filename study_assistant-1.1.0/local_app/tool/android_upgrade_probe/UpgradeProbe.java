package journal.qa;
import android.app.*;
import android.content.*;
import android.os.*;
import java.util.*;
import org.json.*;

/** Emulator-only upgrade fixture. Never included in the application APK. */
public class UpgradeProbe extends Instrumentation {
  Bundle args;
  public void onCreate(Bundle bundle) { args=bundle; start(); }
  Object secure;
  Class<?> storage;
  String prefix(String k) throws Exception { return (String)storage.getMethod("addPrefixToKey",String.class).invoke(secure,k); }
  void write(String k,String v) throws Exception { storage.getMethod("write",String.class,String.class).invoke(secure,prefix(k),v); }
  public void onStart() {
    Bundle result=new Bundle();
    try {
      Context c=getTargetContext();
      storage=Class.forName("com.it_nomads.fluttersecurestorage.FlutterSecureStorage",true,c.getClassLoader());
      Map<String,Object> opts=new HashMap<>(); opts.put("encryptedSharedPreferences","true");
      secure=storage.getConstructor(Context.class,Map.class).newInstance(c,opts);
      SharedPreferences prefs=c.getSharedPreferences("FlutterSharedPreferences",0);
      String mode=args.getString("mode","verify");
      String kind=args.getString("kind","both");
      if(!Arrays.asList("seed","verify").contains(mode) || !Arrays.asList("both","chaoxing","retired").contains(kind)) throw new AssertionError("Unknown fixture mode/kind");
      boolean cx=!kind.equals("retired"), retired=!kind.equals("chaoxing");
      if(mode.equals("seed")) {
        storage.getMethod("deleteAll").invoke(secure);
        for(Map.Entry<String,String> entry : UpgradeFixture.credentials(cx).entrySet()) write(entry.getKey(),entry.getValue());
        if(retired) { write("shuniZuilingSchoolUserLocalId","retired-demo"); write("shuniZuilingPassword","SAMPLE"); write("shuniZuilingSchoolCode","demo"); }
        JSONArray items=new JSONArray();
        if(cx) for(int i=0;i<4;i++) items.put(UpgradeFixture.record(i));
        if(retired) items.put(item("snzl:demo","旧平台测试作业","旧课程","2026-11-04T19:00:00.000"));
        boolean saved=prefs.edit().clear().putString("flutter.local_assignments",items.toString())
          .putString("flutter.local_last_sync_at",UpgradeFixture.SYNC)
          .putString("flutter.local_hidden_completed_assignment_ids",encodeList(cx ? Arrays.asList(UpgradeFixture.id(1), "snzl:demo") : Arrays.asList("snzl:demo")))
          .putString("flutter.unfollowed_courses",encodeList(Arrays.asList("fixture-unfollowed:fixture-class")))
          .putString("flutter.reminder_offsets_minutes","VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu![\"60\",\"10\"]")
          .putLong("flutter.auto_sync_interval_minutes",0).commit();
        if(!saved) throw new AssertionError("Synthetic fixture preferences were not saved");
        result.putString("result","SEEDED_"+kind);
      } else {
        Map<?,?> credentials=(Map<?,?>)storage.getMethod("readAll").invoke(secure);
        JSONObject journal=new JSONObject(prefs.getString("flutter.chaoxing_journal_v2","{}"));
        boolean legacy = prefs.contains("flutter.local_assignments") || prefs.contains("flutter.local_last_sync_at") || prefs.contains("flutter.local_hidden_completed_assignment_ids");
        UpgradeFixture.verify(credentials,journal,readList(prefs,"flutter.reminder_offsets_minutes"),
          readList(prefs,"flutter.unfollowed_courses"),legacy,kind);
        result.putString("result","PASS_"+kind+"_CREDENTIALS_RECORD_FIELDS_STATUS_DEADLINE_HIDDEN_FOLLOW_REMINDERS");
      }
      finish(Activity.RESULT_OK,result);
    } catch(Throwable error) { result.putString("error",error.toString()); finish(Activity.RESULT_CANCELED,result); }
  }
  static String encodeList(List<String> values) { return "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!"+new JSONArray(values).toString(); }
  static List<String> readList(SharedPreferences prefs,String key) throws Exception {
    Object raw=prefs.getAll().get(key);
    if(raw instanceof Set) {
      List<String> values=new ArrayList<>();
      for(Object value:(Set<?>)raw) values.add(value.toString());
      Collections.sort(values, Collections.reverseOrder());
      return values;
    }
    if(!(raw instanceof String)) throw new AssertionError("Missing preference list "+key);
    String text=(String)raw;
    int separator=text.indexOf('!');
    JSONArray values=new JSONArray(separator<0?text:text.substring(separator+1));
    List<String> result=new ArrayList<>();
    for(int i=0;i<values.length();i++) result.add(values.getString(i));
    return result;
  }
  JSONObject item(String id,String title,String course,String deadline) throws Exception {
    JSONObject j=new JSONObject();j.put("id",id);j.put("title",title);j.put("courseName",course);
    j.put("deadlineAt",deadline==null?JSONObject.NULL:deadline);j.put("status","pending");
    j.put("requirementsText","示例数据，仅用于本机升级验收");j.put("lastSyncedAt",UpgradeFixture.SYNC);return j;
  }
}
