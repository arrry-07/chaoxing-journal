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
      boolean cx=!kind.equals("retired"), retired=!kind.equals("chaoxing");
      if(mode.equals("seed")) {
        storage.getMethod("deleteAll").invoke(secure);
        if(cx) {
          write("chaoxingAccount","journal-demo-student"); write("chaoxingPassword","SAMPLE_NOT_A_REAL_PASSWORD");
          write("chaoxingDisplayName","手帐同学 · 示例数据");
        }
        if(retired) { write("shuniZuilingSchoolUserLocalId","retired-demo"); write("shuniZuilingPassword","SAMPLE"); write("shuniZuilingSchoolCode","demo"); }
        JSONArray items=new JSONArray();
        if(cx) {
          String[] titles={"函数极限与连续：习题整理","阅读报告：把晚霞借给你","程序设计综合实验报告与项目复盘","预习下一章，整理想问的问题"};
          String[] courses={"高等数学","大学语文","程序设计","大学英语"};
          String[] dates={"2026-11-04T18:00:00.000","2026-11-04T20:30:00.000","2026-11-04T22:00:00.000","2026-11-05T18:00:00.000"};
          for(int i=0;i<4;i++) items.put(item("cx:demo:"+i,titles[i],courses[i],dates[i]));
        }
        if(retired) items.put(item("snzl:demo","旧平台测试作业","旧课程","2026-11-04T19:00:00.000"));
        prefs.edit().clear().putString("flutter.local_assignments",items.toString())
          .putString("flutter.local_last_sync_at","2026-11-04T08:00:00.000")
          .putString("flutter.reminder_offsets_minutes","VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu![\"60\",\"10\"]")
          .putLong("flutter.auto_sync_interval_minutes",0).commit();
        result.putString("result","SEEDED_"+kind);
      } else {
        Map<?,?> credentials=(Map<?,?>)storage.getMethod("readAll").invoke(secure);
        for(Object key:credentials.keySet()) if(key.toString().startsWith("shuni")) throw new AssertionError("Retired credential survived");
        if(cx != credentials.containsKey("chaoxingAccount")) throw new AssertionError("Account retention mismatch");
        JSONObject journal=new JSONObject(prefs.getString("flutter.chaoxing_journal_v2","{}"));
        JSONArray records=journal.getJSONArray("records");
        if(records.length()!=(cx?4:0)) throw new AssertionError("Record count mismatch "+records.length());
        if(journal.toString().contains("snzl:")) throw new AssertionError("Retired records survived");
        if(!prefs.getString("flutter.reminder_offsets_minutes","").contains("60")) throw new AssertionError("Reminder lost");
        if(prefs.contains("flutter.local_assignments")) throw new AssertionError("Legacy key survived");
        result.putString("result","PASS_"+kind+"_ACCOUNT_RECORDS_REMINDERS");
      }
      finish(Activity.RESULT_OK,result);
    } catch(Throwable error) { result.putString("error",error.toString()); finish(Activity.RESULT_CANCELED,result); }
  }
  JSONObject item(String id,String title,String course,String deadline) throws Exception {
    JSONObject j=new JSONObject();j.put("id",id);j.put("title",title);j.put("courseName",course);
    j.put("deadlineAt",deadline==null?JSONObject.NULL:deadline);j.put("status","pending");
    j.put("requirementsText","示例数据，仅用于本机升级验收");j.put("lastSyncedAt","2026-11-04T08:00:00.000");return j;
  }
}
