package journal.qa;

import com.example.studyassistant.ChaoxingAssignmentLink;
import java.net.URLDecoder;

public class ExamListLinkTest {
    public static void main(String[] args) throws Exception {
        String course = "https://mooc1-api.chaoxing.com/phone/moocAnalysis/examList?courseId=C&classId=K";
        String account = "https://mooc1-api.chaoxing.com/exam-ans/exam/test/examcode/examlist";
        String notices = "https://notice.chaoxing.com/pc/notice/myNotice";
        int count = 0;
        for (String allowed : new String[] {course, account, notices}) {
            String link = ChaoxingAssignmentLink.build(allowed);
            String title = allowed.equals(notices) ? "通知收件箱" : "考试列表";
            if (link == null || !URLDecoder.decode(link, "UTF-8").contains("url=" + allowed + "&title=" + title)) {
                throw new AssertionError("Read-only exam list rejected or changed");
            }
            count++;
        }
        for (String bad : new String[] {
            course.replace("https:", "http:"),
            course.replace("mooc1-api.chaoxing.com", "evil.chaoxing.com"),
            course.replace("mooc1-api.chaoxing.com", "mooc1-api.chaoxing.com.evil.test"),
            course.replace("mooc1-api.chaoxing.com", "user@mooc1-api.chaoxing.com"),
            course.replace("mooc1-api.chaoxing.com", "mooc1-api.chaoxing.com:444"),
            course + "#fragment", course + "&examId=E", course + "&enc=secret",
            course + "&courseId=other", course.replace("courseId=C", "courseId="),
            course.replace("courseId=C", "courseId=C%26examId%3DE"),
            course.replace("&classId=K", ""),
            course.replace("examList", "answer"),
            course.replace("examList", "%65xamList"),
            account + "?examId=E", account + "?url=https://example.test/",
            account.replace("examlist", "answer"),
            "https://notice.chaoxing.com/pc/notice/inbox",
            notices + "?", notices + "?id=message", notices + "#fragment",
            notices.replace("notice.chaoxing.com", "user@notice.chaoxing.com"),
            notices.replace("notice.chaoxing.com", "notice.chaoxing.com.evil.test"),
            notices.replace("myNotice", "noticeDetail"),
            notices.replace("https:", "http:"),
        }) {
            if (ChaoxingAssignmentLink.build(bad) != null) {
                throw new AssertionError("Unsafe exam entry accepted: " + bad);
            }
            count++;
        }
        System.out.println("PASS " + count + " read-only exam list checks");
    }
}
