"""Run existing synthetic JVM checks; no Android device or credentials required."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--json-jar', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
java = Path(os.environ['JAVA_HOME']) / 'bin'
suffix = '.exe' if os.name == 'nt' else ''
source = root / 'android/app/src/main/java/com/example/studyassistant'
for name, main, files in [
    ('backup', 'com.example.studyassistant.BackupCryptoTest', [
        root / 'tool/backup_crypto/BackupCryptoTest.java', source / 'BackupCrypto.java']),
    ('policies', 'journal.qa.NativePoliciesTest', [
        root / 'tool/android_upgrade_probe/NativePoliciesTest.java',
        root / 'tool/android_upgrade_probe/UpgradeFixture.java',
        source / 'BrowserPolicy.java', source / 'ChaoxingAssignmentLink.java'])]:
    out = root / 'build/native-checks' / name
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(java / ('javac' + suffix)), '-encoding', 'UTF-8',
        '-classpath', str(args.json_jar.resolve()), '-d', str(out), *map(str, files)], check=True)
    subprocess.run([str(java / ('java' + suffix)), '-Xmx512m', '-classpath',
        os.pathsep.join([str(out), str(args.json_jar.resolve())]), main], check=True)
