param([Parameter(Mandatory=$true)][string]$Destination,[Parameter(Mandatory=$true)][string]$FlutterSdk,[Parameter(Mandatory=$true)][string]$AndroidSdk)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dest=[IO.Path]::GetFullPath($Destination)
if(Test-Path -LiteralPath $dest){throw 'Destination must not exist; use a new isolated folder.'}
New-Item -ItemType Directory -Path $dest | Out-Null
$archive=Join-Path $dest 'source.zip'
git -C $repo archive v1.6.71 -o $archive
if($LASTEXITCODE -ne 0){throw 'git archive failed'}
Expand-Archive -LiteralPath $archive -DestinationPath $dest
$app=Join-Path $dest 'study_assistant-1.1.0/local_app'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'demo_main.dart') -Destination (Join-Path $app 'lib/demo_main.dart')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'demo_video_test.dart') -Destination (Join-Path $app 'test/demo_video_test.dart')
$gradle=Join-Path $app 'android/app/build.gradle'
[IO.File]::WriteAllText($gradle,([IO.File]::ReadAllText($gradle).Replace('applicationIdSuffix ".journal"','applicationIdSuffix ".journal.demo"')))
$manifest=Join-Path $app 'android/app/src/main/AndroidManifest.xml'
[IO.File]::WriteAllText($manifest,([IO.File]::ReadAllText($manifest).Replace('android:label="学习通课业手记"','android:label="课业手记·演示"').Replace('<uses-permission android:name="android.permission.INTERNET" />','')))
[IO.File]::WriteAllText((Join-Path $app 'android/local.properties'),('sdk.dir='+$AndroidSdk.Replace('\','/')+[Environment]::NewLine+'flutter.sdk='+$FlutterSdk.Replace('\','/')+[Environment]::NewLine))
Push-Location $app
try{
 & (Join-Path $FlutterSdk 'bin/flutter.bat') pub get --enforce-lockfile
 if($LASTEXITCODE -ne 0){throw 'pub get failed'}
 & (Join-Path $FlutterSdk 'bin/flutter.bat') test --no-pub test/demo_video_test.dart
 if($LASTEXITCODE -ne 0){throw 'demo tests failed'}
 & (Join-Path $FlutterSdk 'bin/flutter.bat') build apk --debug --no-pub --target lib/demo_main.dart --target-platform android-x64
 if($LASTEXITCODE -ne 0){throw 'demo build failed'}
}finally{Pop-Location}
Write-Output (Join-Path $app 'build/app/outputs/flutter-apk/app-debug.apk')
