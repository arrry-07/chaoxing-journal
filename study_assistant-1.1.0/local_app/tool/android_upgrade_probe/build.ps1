param([string]$Sdk=$env:ANDROID_HOME,[string]$Jdk=$env:JAVA_HOME,[string]$Output="$PSScriptRoot/../../build/upgrade-probe")
$ErrorActionPreference='Stop'
if(!$Sdk -or !$Jdk){ throw 'Set ANDROID_HOME and JAVA_HOME.' }
$env:JAVA_HOME=$Jdk
$tools="$Sdk/build-tools/35.0.0"
$androidJar="$Sdk/platforms/android-35/android.jar"
New-Item -ItemType Directory -Force "$Output/classes","$Output/dex" | Out-Null
& "$Jdk/bin/javac.exe" -encoding UTF-8 -source 8 -target 8 -classpath $androidJar -d "$Output/classes" "$PSScriptRoot/UpgradeProbe.java"
if($LASTEXITCODE){throw 'javac failed'}
& "$tools/d8.bat" --lib $androidJar --output "$Output/dex" "$Output/classes/journal/qa/UpgradeProbe.class"
if($LASTEXITCODE){throw 'd8 failed'}
& "$tools/aapt2.exe" link -I $androidJar --manifest "$PSScriptRoot/AndroidManifest.xml" -o "$Output/probe.apk"
& "$Jdk/bin/jar.exe" uf "$Output/probe.apk" -C "$Output/dex" classes.dex
& "$tools/apksigner.bat" sign --ks "$env:USERPROFILE/.android/debug.keystore" --ks-pass pass:android "$Output/probe.apk"
if($LASTEXITCODE){throw 'sign failed'}
Write-Output "$Output/probe.apk"
