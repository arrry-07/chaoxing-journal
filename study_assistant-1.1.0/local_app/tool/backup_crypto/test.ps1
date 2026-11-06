param(
  [string]$Jdk = 'D:/campus-tools/jdk17.0.21_0',
  [string]$JsonJar,
  [string]$Output = "$PSScriptRoot/../../build/backup-crypto-tests"
)
$ErrorActionPreference = 'Stop'
if (!$JsonJar) {
  $JsonJar = Get-ChildItem -LiteralPath "$env:USERPROFILE/.gradle/caches/modules-2/files-2.1/org.json/json" -Filter '*.jar' -Recurse |
    Select-Object -First 1 -ExpandProperty FullName
}
if (!$JsonJar) { throw 'Provide -JsonJar pointing to an org.json JVM jar.' }
New-Item -ItemType Directory -Force $Output | Out-Null
$sources = @("$PSScriptRoot/BackupCryptoTest.java", "$PSScriptRoot/../../android/app/src/main/java/com/example/studyassistant/BackupCrypto.java")
& "$Jdk/bin/javac.exe" -encoding UTF-8 -classpath $JsonJar -d $Output @sources
if ($LASTEXITCODE) { throw 'Backup crypto tests failed to compile.' }
& "$Jdk/bin/java.exe" -Xmx512m -classpath "$Output;$JsonJar" com.example.studyassistant.BackupCryptoTest
if ($LASTEXITCODE) { throw 'Backup crypto tests failed.' }
