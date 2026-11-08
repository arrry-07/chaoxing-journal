package com.example.studyassistant;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Pure architecture checks shared by the Android update gate and JVM tests. */
public final class UpdateApkPolicy {
    private UpdateApkPolicy() {}

    public static boolean hasSupportedFlutterEngine(
            List<String> nativePaths, List<String> supportedAbis) {
        Set<String> declaredAbis = new HashSet<>();
        Set<String> engineAbis = new HashSet<>();
        for (String path : nativePaths) {
            String[] parts = path.split("/", 3);
            if (parts.length != 3 || !"lib".equals(parts[0]) || !parts[2].endsWith(".so")) {
                continue;
            }
            declaredAbis.add(parts[1]);
            if ("libflutter.so".equals(parts[2])) engineAbis.add(parts[1]);
        }
        if (engineAbis.isEmpty() || !declaredAbis.equals(engineAbis)) return false;
        for (String abi : supportedAbis) {
            if (engineAbis.contains(abi)) return true;
        }
        return false;
    }
}
