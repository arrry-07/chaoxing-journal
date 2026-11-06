package com.example.studyassistant;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import org.json.JSONObject;
import org.json.JSONTokener;

/** Portable v1 password backup. Only this exact authenticated suite is accepted. */
public final class BackupCrypto {
    public static final int MAX_PLAINTEXT_BYTES = 8 * 1024 * 1024;
    public static final int MAX_ENVELOPE_BYTES = 12 * 1024 * 1024;
    private static final int ITERATIONS = 600_000;
    private static final String FORMAT = "study-assistant-backup";
    private static final String KDF = "PBKDF2-HMAC-SHA256";
    private static final String CIPHER = "AES-256-GCM";
    private static final byte[] AAD = (FORMAT + "\n1\n" + KDF + "\n" + ITERATIONS + "\n" + CIPHER)
        .getBytes(StandardCharsets.US_ASCII);
    private static final SecureRandom RANDOM = new SecureRandom();
    private BackupCrypto() {}

    public static String encrypt(String plaintext, char[] password) throws Exception {
        byte[] bytes = null;
        try {
            validatePassword(password);
            if (plaintext == null || plaintext.isEmpty() || plaintext.length() > MAX_PLAINTEXT_BYTES)
                throw new IllegalArgumentException("Invalid backup size");
            bytes = plaintext.getBytes(StandardCharsets.UTF_8);
            if (bytes.length > MAX_PLAINTEXT_BYTES) throw new IllegalArgumentException("Backup too large");
            byte[] salt = new byte[16];
            byte[] iv = new byte[12];
            RANDOM.nextBytes(salt);
            RANDOM.nextBytes(iv);
            Cipher cipher = cipher(Cipher.ENCRYPT_MODE, password, salt, iv);
            byte[] encrypted = cipher.doFinal(bytes);
            return new JSONObject().put("format", FORMAT).put("version", 1)
                .put("iterations", ITERATIONS).put("kdf", KDF).put("cipher", CIPHER)
                .put("salt", encode(salt)).put("iv", encode(iv))
                .put("ciphertext", encode(encrypted)).toString();
        } finally {
            if (bytes != null) Arrays.fill(bytes, (byte) 0);
            clearPassword(password);
        }
    }

    public static String decrypt(String envelope, char[] password) throws Exception {
        byte[] plaintext = null;
        try {
            validatePassword(password);
            if (envelope == null || envelope.isEmpty() || envelope.length() > MAX_ENVELOPE_BYTES ||
                envelope.getBytes(StandardCharsets.UTF_8).length > MAX_ENVELOPE_BYTES)
                throw new IllegalArgumentException("Invalid backup size");
            rejectNestedJson(envelope);
            JSONTokener tokens = new JSONTokener(envelope);
            JSONObject json = new JSONObject(tokens);
            if (tokens.nextClean() != 0) throw new IllegalArgumentException("Invalid backup structure");
            if (json.length() != 8 || !FORMAT.equals(json.get("format")) ||
                !integerEquals(json.get("version"), 1) || !KDF.equals(json.get("kdf")) ||
                !CIPHER.equals(json.get("cipher")) || !integerEquals(json.get("iterations"), ITERATIONS))
                throw new IllegalArgumentException("Unsupported backup format");
            byte[] salt = decode(json.get("salt"), 16, 16);
            byte[] iv = decode(json.get("iv"), 12, 12);
            byte[] ciphertext = decode(json.get("ciphertext"), 17, MAX_PLAINTEXT_BYTES + 16);
            plaintext = cipher(Cipher.DECRYPT_MODE, password, salt, iv).doFinal(ciphertext);
            if (plaintext.length == 0 || plaintext.length > MAX_PLAINTEXT_BYTES)
                throw new IllegalArgumentException("Invalid backup size");
            return decodeUtf8(plaintext);
        } finally {
            if (plaintext != null) Arrays.fill(plaintext, (byte) 0);
            clearPassword(password);
        }
    }

    // Reject nested objects before JSONObject recursion, including malicious depth bombs.
    private static void rejectNestedJson(String value) {
        boolean quoted = false, escaped = false;
        char quote = 0;
        int objects = 0;
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (quoted) {
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == quote) quoted = false;
            } else if (c == '"' || c == '\'') {
                quoted = true;
                quote = c;
            } else if (c == '[' || c == ']' || (c == '{' && ++objects > 1)) {
                throw new IllegalArgumentException("Invalid backup structure");
            }
        }
    }

    private static boolean integerEquals(Object value, int expected) {
        return (value instanceof Integer || value instanceof Long) && ((Number) value).longValue() == expected;
    }

    private static Cipher cipher(int mode, char[] password, byte[] salt, byte[] iv) throws GeneralSecurityException {
        PBEKeySpec spec = new PBEKeySpec(password, salt, ITERATIONS, 256);
        byte[] key = null;
        try {
            key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(mode, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, iv));
            cipher.updateAAD(AAD);
            return cipher;
        } finally {
            spec.clearPassword();
            if (key != null) Arrays.fill(key, (byte) 0);
        }
    }

    private static String encode(byte[] value) { return Base64.getEncoder().encodeToString(value); }
    private static byte[] decode(Object value, int min, int max) {
        if (!(value instanceof String)) throw new IllegalArgumentException("Invalid encoding");
        String encoded = (String) value;
        if (encoded.length() > ((max + 2) / 3) * 4) throw new IllegalArgumentException("Invalid encoding size");
        byte[] bytes = Base64.getDecoder().decode(encoded);
        if (bytes.length < min || bytes.length > max || !encode(bytes).equals(encoded))
            throw new IllegalArgumentException("Invalid encoding");
        return bytes;
    }

    private static void validatePassword(char[] password) {
        if (password == null || password.length == 0 || password.length > 1024)
            throw new IllegalArgumentException("Invalid password length");
    }
    private static void clearPassword(char[] password) {
        if (password != null) Arrays.fill(password, '\0');
    }

    /** Read at most the envelope limit even when a provider reports a false file size. */
    public static byte[] readBounded(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (count == 0) continue;
            if (output.size() > MAX_ENVELOPE_BYTES - count) throw new IOException("Backup too large");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    public static String decodeUtf8(byte[] bytes) throws CharacterCodingException {
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
    }
}
