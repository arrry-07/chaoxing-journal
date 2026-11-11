#Requires -Version 5.1
# Generate one strict update manifest for the stable or manual entry. This
# script does not upload the APK or manifest.
#
# Usage:
#   powershell -File scripts/update-manifest.ps1 `
#     -ApkPath artifacts/current/release-1.6.3/chaoxing-journal-1.6.3.apk `
#     -VersionName 1.7.3 -VersionCode 55 -Channel stable `
#     -PreviousVersionName 1.6.72 -PreviousVersionCode 54 `
#     -BaseUrl https://updates.example.org `
#     -OutPath artifacts/current/release-1.7.3/update-stable.json
param(
  [Parameter(Mandatory = $true)][string]$ApkPath,
  [Parameter(Mandatory = $true)][string]$VersionName,
  [Parameter(Mandatory = $true)][int]$VersionCode,
  [Parameter(Mandatory = $true)][ValidateSet('stable', 'manual')][string]$Channel,
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [string]$OutPath = '',
  [string]$ApplicationId = 'com.example.studyassistant.journal',
  [string]$Notes = '',
  [string]$PreviousVersionName = '',
  [int]$PreviousVersionCode = 0,
  [string]$BackupApkUrl = '',
  [string]$AaptPath = '',
  [string]$ApkSignerPath = '',
  [string]$ExpectedSignerSha256 = 'd36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a'
)

if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
  throw 'VersionName must contain exactly three numeric parts, for example 1.7.3.'
}
if ($VersionCode -le 0 -or $VersionCode -gt 2147483647) {
  throw 'VersionCode must be a positive Android versionCode.'
}
if ($ApplicationId -ne 'com.example.studyassistant.journal') {
  throw 'ApplicationId must exactly match com.example.studyassistant.journal.'
}

$baseUri = [System.Uri]$null
if (-not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$baseUri) -or
    $baseUri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($baseUri.Host) -or
    -not [string]::IsNullOrWhiteSpace($baseUri.UserInfo) -or
    -not [string]::IsNullOrWhiteSpace($baseUri.Query) -or
    -not [string]::IsNullOrWhiteSpace($baseUri.Fragment)) {
  throw 'BaseUrl must be an HTTPS URL without embedded credentials.'
}
if (-not [string]::IsNullOrWhiteSpace($BackupApkUrl)) {
  $backupUri = [System.Uri]$null
  if (-not [System.Uri]::TryCreate($BackupApkUrl, [System.UriKind]::Absolute, [ref]$backupUri) -or
      $backupUri.Scheme -ne 'https' -or
      [string]::IsNullOrWhiteSpace($backupUri.Host) -or
      -not [string]::IsNullOrWhiteSpace($backupUri.UserInfo)) {
    throw 'BackupApkUrl must be an HTTPS URL without embedded credentials.'
  }
}

if (-not [string]::IsNullOrWhiteSpace($PreviousVersionName)) {
  if ($PreviousVersionName -notmatch '^\d+\.\d+\.\d+$') {
    throw 'PreviousVersionName must contain exactly three numeric parts.'
  }
}
if ([string]::IsNullOrWhiteSpace($PreviousVersionName) -or
    $PreviousVersionCode -le 0) {
  throw 'PreviousVersionName and PreviousVersionCode are required to prevent stale manifests.'
}
$current = $VersionName.Split('.') | ForEach-Object { [int]$_ }
$previous = $PreviousVersionName.Split('.') | ForEach-Object { [int]$_ }
$newIteration = $current[0] -gt $previous[0] -or
    ($current[0] -eq $previous[0] -and $current[1] -gt $previous[1])
if ($Channel -eq 'stable' -and -not $newIteration) {
  throw 'Stable manifests may only advance the major or minor version.'
}
if ($VersionCode -le $PreviousVersionCode) {
  throw 'VersionCode must be greater than PreviousVersionCode.'
}
if (-not $newIteration -and
    ($current[0] -lt $previous[0] -or
     ($current[0] -eq $previous[0] -and $current[1] -lt $previous[1]) -or
     ($current[0] -eq $previous[0] -and
      $current[1] -eq $previous[1] -and
      $current[2] -lt $previous[2]))) {
  throw 'VersionName must not move backwards from PreviousVersionName.'
}

$apk = Get-Item -LiteralPath $ApkPath
if ($apk.PSIsContainer -or $apk.Extension -ne '.apk') {
  throw 'ApkPath must point to a file with the .apk extension.'
}
$stream = [System.IO.File]::OpenRead($apk.FullName)
try {
  $signature = New-Object byte[] 2
  $read = $stream.Read($signature, 0, $signature.Length)
} finally {
  $stream.Dispose()
}
if ($read -ne 2 -or $signature[0] -ne 0x50 -or $signature[1] -ne 0x4b) {
  throw 'ApkPath does not start with an APK/ZIP signature.'
}

function Resolve-AndroidTool([string]$ExplicitPath, [string]$Name) {
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    $item = Get-Item -LiteralPath $ExplicitPath -ErrorAction Stop
    if ($item.PSIsContainer) {
      throw "$Name path must point to an executable file."
    }
    return $item.FullName
  }
  $sdk = if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) {
    $env:ANDROID_HOME
  } else {
    $env:ANDROID_SDK_ROOT
  }
  if ([string]::IsNullOrWhiteSpace($sdk)) {
    throw "$Name was not provided and ANDROID_HOME/ANDROID_SDK_ROOT is empty."
  }
  $buildTools = Join-Path $sdk 'build-tools'
  if (-not [System.IO.Directory]::Exists($buildTools)) {
    throw "$Name was not provided and Android build-tools is missing."
  }
  $executables = @(
    if ($env:OS -eq 'Windows_NT') { "$Name.exe"; "$Name.bat" } else { $Name }
  )
  foreach ($directory in (Get-ChildItem -LiteralPath $buildTools -Directory |
      Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending)) {
    foreach ($executable in $executables) {
      $candidate = Join-Path $directory.FullName $executable
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Get-Item -LiteralPath $candidate).FullName
      }
    }
  }
  throw "$Name was not found under Android build-tools."
}

$aapt = Resolve-AndroidTool $AaptPath 'aapt'
$apksigner = Resolve-AndroidTool $ApkSignerPath 'apksigner'
$badging = & $aapt dump badging $apk.FullName 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw 'aapt failed to inspect the APK identity.'
}
$identity = [regex]::Match(
  $badging,
  "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'"
)
if (-not $identity.Success) {
  throw 'Could not parse APK applicationId, versionCode or versionName.'
}
if ($identity.Groups[1].Value -ne $ApplicationId) {
  throw "APK applicationId '$($identity.Groups[1].Value)' does not match '$ApplicationId'."
}
if ($identity.Groups[2].Value -ne "$VersionCode") {
  throw "APK versionCode '$($identity.Groups[2].Value)' does not match '$VersionCode'."
}
if ($identity.Groups[3].Value -ne $VersionName) {
  throw "APK versionName '$($identity.Groups[3].Value)' does not match '$VersionName'."
}
$signatureOutput = & $apksigner verify --verbose --print-certs $apk.FullName 2>&1 |
    Out-String
if ($LASTEXITCODE -ne 0) {
  throw 'apksigner rejected the APK signature.'
}
$signer = [regex]::Match(
  $signatureOutput,
  'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)'
)
$expectedSigner = $ExpectedSignerSha256.Replace(':', '').ToLowerInvariant()
if (-not $signer.Success -or
    $signer.Groups[1].Value.Replace(':', '').ToLowerInvariant() -ne $expectedSigner) {
  throw 'APK signer does not match the registered release certificate.'
}

$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk.FullName).Hash.ToLowerInvariant()
$versionKey = "$VersionName-$VersionCode"
$apkFileName = "chaoxing-journal-$versionKey.apk"
$apkUrl = "$($BaseUrl.TrimEnd('/'))/$versionKey/$apkFileName"
$manifest = [ordered]@{
  versionCode   = $VersionCode
  versionName   = $VersionName
  apkUrl        = $apkUrl
  sha256        = $sha
  applicationId = $ApplicationId
  notes         = $Notes
  size          = $apk.Length
}
if (-not [string]::IsNullOrWhiteSpace($BackupApkUrl)) {
  $manifest.backupApkUrl = $BackupApkUrl
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
  $OutPath = Join-Path (Split-Path -Parent $apk.FullName) "update-$Channel.json"
}
$outFullPath = [System.IO.Path]::GetFullPath($OutPath)
if ($outFullPath -eq $apk.FullName) {
  throw 'OutPath must not overwrite the APK.'
}
$outDirectory = [System.IO.Path]::GetDirectoryName($outFullPath)
if (-not [System.IO.Directory]::Exists($outDirectory)) {
  [System.IO.Directory]::CreateDirectory($outDirectory) | Out-Null
}
$json = $manifest | ConvertTo-Json -Compress
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outFullPath, $json, $utf8NoBom)
Write-Output ("manifest written: " + $outFullPath)
Write-Output ("channel         : " + $Channel)
Write-Output ("unique apk path : " + $apkUrl)
Write-Output ("apk size bytes : " + $apk.Length)
Write-Output ("apk sha256     : " + $sha)
