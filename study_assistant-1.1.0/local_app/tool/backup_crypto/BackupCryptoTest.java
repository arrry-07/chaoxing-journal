package com.example.studyassistant;

import java.io.ByteArrayInputStream;
import java.util.Arrays;
import org.json.JSONObject;

public final class BackupCryptoTest {
    interface Checked { void run() throws Exception; }
    static int checks;
    static void check(boolean ok) { if (!ok) throw new AssertionError(); checks++; }
    static void rejects(Checked action) throws Exception {
        try { action.run(); } catch (Exception expected) { checks++; return; }
        throw new AssertionError("Expected rejection");
    }
    static String encrypt(String text) throws Exception {
        char[] password = "test 密码 123456".toCharArray();
        String result = BackupCrypto.encrypt(text, password);
        check(Arrays.equals(password, new char[password.length]));
        return result;
    }
    public static void main(String[] args) throws Exception {
        String text = "{\"note\":\"测试中文🙂\"}";
        String envelope = encrypt(text);
        char[] password = "test 密码 123456".toCharArray();
        check(text.equals(BackupCrypto.decrypt(envelope, password)));
        check(Arrays.equals(password, new char[password.length]));
        rejects(() -> BackupCrypto.decrypt(envelope, "wrong".toCharArray()));
        String second = encrypt(text);
        check(!new JSONObject(envelope).getString("salt").equals(new JSONObject(second).getString("salt")));
        check(!new JSONObject(envelope).getString("iv").equals(new JSONObject(second).getString("iv")));
        for (String field : new String[]{"salt", "iv", "ciphertext"}) {
            JSONObject changed = new JSONObject(envelope);
            String encoded = changed.getString(field);
            changed.put(field, (encoded.charAt(0) == 'A' ? "B" : "A") + encoded.substring(1));
            rejects(() -> BackupCrypto.decrypt(changed.toString(), "test 密码 123456".toCharArray()));
        }
        for (Object value : new Object[]{1, 599999, 600001, Integer.MAX_VALUE, "600000", 600000.5}) {
            JSONObject changed = new JSONObject(envelope).put("iterations", value);
            rejects(() -> BackupCrypto.decrypt(changed.toString(), "test 密码 123456".toCharArray()));
        }
        for (String field : new String[]{"format", "version", "cipher", "kdf"}) {
            JSONObject changed = new JSONObject(envelope).put(field, "unknown");
            rejects(() -> BackupCrypto.decrypt(changed.toString(), "test 密码 123456".toCharArray()));
        }
        rejects(() -> BackupCrypto.decrypt(new JSONObject(envelope).put("extra", true).toString(), "test".toCharArray()));
        rejects(() -> BackupCrypto.decrypt("{}", "test".toCharArray()));
        rejects(() -> BackupCrypto.decrypt(envelope + " garbage", "test 密码 123456".toCharArray()));
        rejects(() -> BackupCrypto.decrypt("{\"nested\":" + "[".repeat(10000), "test".toCharArray()));
        rejects(() -> BackupCrypto.decrypt(new JSONObject(envelope).put("iv", "AA==").toString(), "test".toCharArray()));
        rejects(() -> BackupCrypto.decrypt(new JSONObject(envelope).put("salt", JSONObject.NULL).toString(), "test".toCharArray()));
        rejects(() -> BackupCrypto.decrypt(" ".repeat(12 * 1024 * 1024 + 1), "test".toCharArray()));
        rejects(() -> BackupCrypto.encrypt("", "test".toCharArray()));
        rejects(() -> BackupCrypto.encrypt("a", new char[0]));
        rejects(() -> BackupCrypto.encrypt("a", new char[1025]));
        rejects(() -> BackupCrypto.encrypt("a".repeat(8 * 1024 * 1024 + 1), "test".toCharArray()));
        rejects(() -> BackupCrypto.encrypt("中".repeat(3 * 1024 * 1024), "test".toCharArray()));
        String maximum = "a".repeat(8 * 1024 * 1024);
        check(maximum.equals(BackupCrypto.decrypt(encrypt(maximum), "test 密码 123456".toCharArray())));
        byte[] file = new byte[12 * 1024 * 1024];
        check(BackupCrypto.readBounded(new ByteArrayInputStream(file)).length == file.length);
        rejects(() -> BackupCrypto.readBounded(new ByteArrayInputStream(new byte[file.length + 1])));
        rejects(() -> BackupCrypto.decodeUtf8(new byte[]{(byte) 0xc3, 0x28}));
        char[] failedPassword = "secret".toCharArray();
        rejects(() -> BackupCrypto.decrypt("{}", failedPassword));
        check(Arrays.equals(failedPassword, new char[failedPassword.length]));
        char[] failedEncryptionPassword = "secret".toCharArray();
        rejects(() -> BackupCrypto.encrypt("", failedEncryptionPassword));
        check(Arrays.equals(failedEncryptionPassword, new char[failedEncryptionPassword.length]));
        System.out.println("PASS BackupCrypto: " + checks + " checks");
    }
}
