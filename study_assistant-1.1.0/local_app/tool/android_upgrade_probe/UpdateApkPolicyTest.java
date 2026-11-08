package com.example.studyassistant;

import java.util.List;

public final class UpdateApkPolicyTest {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        check(UpdateApkPolicy.hasSupportedFlutterEngine(
                List.of(
                        "lib/arm64-v8a/libflutter.so",
                        "lib/arm64-v8a/libapp.so",
                        "lib/x86_64/libflutter.so"),
                List.of("arm64-v8a", "armeabi-v7a")),
                "a supported engine ABI should pass");

        check(!UpdateApkPolicy.hasSupportedFlutterEngine(
                List.of("lib/arm64-v8a/libapp.so"),
                List.of("arm64-v8a")),
                "an APK without a Flutter engine must fail closed");

        check(!UpdateApkPolicy.hasSupportedFlutterEngine(
                List.of(
                        "lib/arm64-v8a/libflutter.so",
                        "lib/armeabi-v7a/libextra.so"),
                List.of("arm64-v8a")),
                "an engine ABI plus an unsupported auxiliary ABI must fail");

        check(!UpdateApkPolicy.hasSupportedFlutterEngine(
                List.of("lib/arm64-v8a/libflutter.so"),
                List.of("x86_64")),
                "an engine for an unsupported device ABI must fail");

        System.out.println("UpdateApkPolicyTest passed");
    }
}
