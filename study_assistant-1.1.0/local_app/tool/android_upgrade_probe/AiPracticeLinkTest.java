package journal.qa;

import com.example.studyassistant.ChaoxingAssignmentLink;

public class AiPracticeLinkTest {
    public static void main(String[] args) {
        String url = "https://mooc2-ans.chaoxing.com/ai-evaluate/v2/redirect/active/stu?courseid=7&clazzid=11&publishUuid=11111111-1111-4111-8111-111111111111";
        if (ChaoxingAssignmentLink.build(url) == null) throw new AssertionError("AI student entry rejected");
        for (String bad : new String[] {
            url.replace("/active/stu", "/active/tea"),
            url.replace("mooc2-ans.chaoxing.com", "evil.chaoxing.com"),
            url + "&classId=other", url + "&publishUuid=other",
            url.replace("publishUuid=", "missing="),
            url.replace("https:", "http:"), url + "#fragment"
        }) {
            if (ChaoxingAssignmentLink.build(bad) != null) throw new AssertionError("Unsafe AI entry accepted");
        }
        System.out.println("PASS 8 AI student entry checks");
    }
}
