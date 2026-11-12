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
  [string]$BaseUrl = '',
  [string]$ApkUrl = '',
  # Offline candidate only: never writes the stable entry or proves remote absence.
  [switch]$InitializeStableBaselinePreflight,
  [string]$VerifiedLatestEvidencePath = '',
  [string]$StableEntryPath = '',
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

$ErrorActionPreference = 'Stop'
$registeredSigner = 'd36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a'
if ($ExpectedSignerSha256.Replace(':', '').ToLowerInvariant() -cne $registeredSigner) {
  throw 'ExpectedSignerSha256 must remain the registered release certificate.'
}

if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
  throw 'VersionName must contain exactly three numeric parts, for example 1.7.3.'
}
if ($VersionCode -le 0 -or $VersionCode -gt 2147483647) {
  throw 'VersionCode must be a positive Android versionCode.'
}
if ($ApplicationId -ne 'com.example.studyassistant.journal') {
  throw 'ApplicationId must exactly match com.example.studyassistant.journal.'
}

function Assert-HttpsUrl([string]$Value, [string]$Name, [switch]$Base) {
  $uri = [System.Uri]$null
  if ($Value -cne $Value.Trim() -or $Value -match '[\x00-\x20\\]' -or
      -not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
      $uri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host) -or
      -not [string]::IsNullOrEmpty($uri.UserInfo) -or
      -not [string]::IsNullOrEmpty($uri.Fragment) -or
      ($Base -and -not [string]::IsNullOrEmpty($uri.Query))) {
    # Do not echo a rejected URL: it might contain a credential.
    throw "$Name must be an HTTPS URL without embedded credentials or fragments."
  }
}
$hasBase = -not [string]::IsNullOrWhiteSpace($BaseUrl)
$hasApk = -not [string]::IsNullOrWhiteSpace($ApkUrl)
if ($hasBase -eq $hasApk) {
  throw 'Provide exactly one of ApkUrl or BaseUrl.'
}
if ($hasBase) { Assert-HttpsUrl $BaseUrl 'BaseUrl' -Base }
if ($hasApk) { Assert-HttpsUrl $ApkUrl 'ApkUrl' }
if (-not [string]::IsNullOrWhiteSpace($BackupApkUrl)) {
  Assert-HttpsUrl $BackupApkUrl 'BackupApkUrl'
}

if ($InitializeStableBaselinePreflight) {
  if ($Channel -ne 'stable' -or $PSBoundParameters.ContainsKey('PreviousVersionName') -or
      $PSBoundParameters.ContainsKey('PreviousVersionCode')) {
    throw 'Baseline preflight requires stable and forbids PreviousVersion inputs.'
  }
  if ([string]::IsNullOrWhiteSpace($VerifiedLatestEvidencePath) -or
      [string]::IsNullOrWhiteSpace($StableEntryPath)) {
    throw 'Baseline preflight requires VerifiedLatestEvidencePath and StableEntryPath.'
  }
  if (Test-Path -LiteralPath $StableEntryPath) {
    throw 'Stable entry already exists; baseline preflight cannot overwrite it.'
  }
} else {
  if ($PSBoundParameters.ContainsKey('VerifiedLatestEvidencePath') -or
      $PSBoundParameters.ContainsKey('StableEntryPath')) {
    throw 'Baseline evidence inputs require InitializeStableBaselinePreflight.'
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
}

if (-not (Test-Path -LiteralPath $ApkPath)) {
  throw "ApkPath does not exist: $ApkPath"
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
    if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
      throw "$Name path does not exist: $ExplicitPath"
    }
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
if ($hasBase) {
  $ApkUrl = "$($BaseUrl.TrimEnd('/'))/$versionKey/$apkFileName"
}
if ($InitializeStableBaselinePreflight) {
  # Evidence is a maintainer-verified offline snapshot, NOT remote authentication.
  # JSON: { verified: true, verifiedAtUtc: ISO8601, sourceUrl: the official
  # /releases/latest API URL, versionCode: integer, release: raw API response }.
  # release.assets must include the official APK with size and sha256 digest.
  $evidence = Get-Content -Raw -LiteralPath $VerifiedLatestEvidencePath | ConvertFrom-Json
  $official = 'https://api.github.com/repos/arrry-07/chaoxing-journal/releases/latest'
  $verifiedAt = [DateTimeOffset]::MinValue
  if ($evidence.verified -isnot [bool] -or $evidence.verified -ne $true -or
      $evidence.sourceUrl -cne $official -or
      -not [DateTimeOffset]::TryParse([string]$evidence.verifiedAtUtc, [ref]$verifiedAt) -or
      $verifiedAt -gt [DateTimeOffset]::UtcNow -or
      $verifiedAt -lt [DateTimeOffset]::UtcNow.AddHours(-24) -or
      $evidence.versionCode -ne $VersionCode) {
    throw 'Baseline requires a maintainer-verified official latest snapshot from the last 24 hours.'
  }
  $release = $evidence.release
  $releaseUrl = "https://github.com/arrry-07/chaoxing-journal/releases/tag/v$VersionName"
  if ($null -eq $release -or $release.tag_name -cne "v$VersionName" -or
      $release.html_url -cne $releaseUrl -or
      $release.draft -isnot [bool] -or $release.draft -ne $false -or
      $release.prerelease -isnot [bool] -or $release.prerelease -ne $false -or
      [string]::IsNullOrWhiteSpace([string]$release.published_at)) {
    throw 'Baseline evidence must identify a published, non-draft, non-prerelease official latest release.'
  }
  $officialName = "chaoxing-journal-$VersionName.apk"
  $assets = @($release.assets | Where-Object { $_.name -ceq $officialName })
  if ($assets.Count -ne 1 -or
      $assets[0].browser_download_url -cne "https://github.com/arrry-07/chaoxing-journal/releases/download/v$VersionName/$officialName" -or
      $assets[0].size -ne $apk.Length -or
      $assets[0].digest -cne "sha256:$sha") {
    throw 'Baseline APK bytes must match the official latest asset size and SHA-256 digest.'
  }
}
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
  $fileName = if ($InitializeStableBaselinePreflight) { 'update-stable.preflight.json' } else { "update-$Channel.json" }
  $OutPath = Join-Path (Split-Path -Parent $apk.FullName) $fileName
}
$outFullPath = [System.IO.Path]::GetFullPath($OutPath)
if ($outFullPath -eq $apk.FullName) {
  throw 'OutPath must not overwrite the APK.'
}
if ($InitializeStableBaselinePreflight) {
  if ($outFullPath -eq [System.IO.Path]::GetFullPath($StableEntryPath) -or
      $outFullPath -eq (Get-Item -LiteralPath $VerifiedLatestEvidencePath).FullName) {
    throw 'Preflight output must not overwrite the stable entry or evidence.'
  }
  if ((Test-Path -LiteralPath $StableEntryPath) -or (Test-Path -LiteralPath $outFullPath)) {
    throw 'Stable entry or preflight output already exists; refusing overwrite.'
  }
}
$outDirectory = [System.IO.Path]::GetDirectoryName($outFullPath)
if (-not [System.IO.Directory]::Exists($outDirectory)) {
  [System.IO.Directory]::CreateDirectory($outDirectory) | Out-Null
}
$json = $manifest | ConvertTo-Json -Compress
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
if ($InitializeStableBaselinePreflight) {
  $output = [System.IO.File]::Open($outFullPath, [System.IO.FileMode]::CreateNew)
  try {
    $bytes = $utf8NoBom.GetBytes($json)
    $output.Write($bytes, 0, $bytes.Length)
  } finally { $output.Dispose() }
  Write-Output 'OFFLINE PREFLIGHT ONLY: remote stable absence is unverified; initialization is NOT complete.'
} else {
  [System.IO.File]::WriteAllText($outFullPath, $json, $utf8NoBom)
}
Write-Output ("manifest written: " + $outFullPath)
Write-Output ("channel         : " + $Channel)
Write-Output ("unique apk path : " + $apkUrl)
Write-Output ("apk size bytes : " + $apk.Length)
Write-Output ("apk sha256     : " + $sha)
