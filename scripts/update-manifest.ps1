#Requires -Version 5.1
# Generate the domestic update manifest (update.json) consumed by the App
# when it is built with:
#   --dart-define=UPDATE_MANIFEST_URL=https://<bucket>.cos.<region>.myqcloud.com/update.json
# Usage:
#   powershell -File scripts/update-manifest.ps1 `
#     -ApkPath artifacts/current/release-1.6.3/chaoxing-journal-1.6.3.apk `
#     -VersionName 1.6.3 -VersionCode 48 `
#     -ApkUrl https://<bucket>.cos.<region>.myqcloud.com/updates/chaoxing-journal-1.6.3.apk `
#     -OutPath artifacts/current/release-1.6.3/update.json -Notes "release notes"
param(
  [Parameter(Mandatory = $true)][string]$ApkPath,
  [Parameter(Mandatory = $true)][string]$VersionName,
  [Parameter(Mandatory = $true)][int]$VersionCode,
  [Parameter(Mandatory = $true)][string]$ApkUrl,
  [Parameter(Mandatory = $true)][string]$OutPath,
  [string]$ApplicationId = 'com.example.studyassistant.journal',
  [string]$Notes = ''
)
$apk = Get-Item -LiteralPath $ApkPath
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk.FullName).Hash.ToLowerInvariant()
$manifest = [ordered]@{
  versionCode   = $VersionCode
  versionName   = $VersionName
  apkUrl        = $ApkUrl
  sha256        = $sha
  applicationId = $ApplicationId
  notes         = $Notes
  size          = $apk.Length
}
($manifest | ConvertTo-Json -Compress) | Set-Content -LiteralPath $OutPath -Encoding utf8
Write-Output ("manifest written: " + $OutPath)
Write-Output ("apk size bytes : " + $apk.Length)
Write-Output ("apk sha256     : " + $sha)
