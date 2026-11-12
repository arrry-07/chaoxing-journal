#Requires -Version 5.1
# Dependency-free offline execution tests. All APK bytes, evidence and tool output
# are synthetic; these tests do not establish release authenticity or deployment.
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'update-manifest.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('manifest-test-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$passed = 0
$failed = 0
$cert = 'd36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a'
$utf8 = [Text.UTF8Encoding]::new($false)
function Assert($Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
try {
  $apk = Join-Path $root 'synthetic.apk'
  [IO.File]::WriteAllBytes($apk, [byte[]](0x50, 0x4b, 3, 4, 10, 20))
  $aapt = Join-Path $root 'fake-aapt.ps1'
  $signer = Join-Path $root 'fake-apksigner.ps1'
  # Script-scoped configuration is visible to fake tools invoked by the target;
  # LASTEXITCODE models a real native tool, including nonzero failures.
  [IO.File]::WriteAllText($aapt, @'
Add-Content -LiteralPath $testLog -Value ('aapt|' + ($args -join '|'))
$global:LASTEXITCODE = $aaptExit
Write-Output $badging
'@, $utf8)
  [IO.File]::WriteAllText($signer, @'
Add-Content -LiteralPath $testLog -Value ('apksigner|' + ($args -join '|'))
$global:LASTEXITCODE = $signerExit
Write-Output $signerOutput
'@, $utf8)
  $evidencePath = Join-Path $root 'verified-latest.json'
  $stable = Join-Path $root 'update-stable.json'
  function New-Evidence {
    @{
      verified = $true
      verifiedAtUtc = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
      sourceUrl = 'https://api.github.com/repos/arrry-07/chaoxing-journal/releases/latest'
      versionCode = 57
      release = @{
        tag_name = 'v1.7.5'
        html_url = 'https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.5'
        draft = $false; prerelease = $false; published_at = '2026-11-12T00:00:00Z'
        assets = @(@{
          name = 'chaoxing-journal-1.7.5.apk'
          browser_download_url = 'https://github.com/arrry-07/chaoxing-journal/releases/download/v1.7.5/chaoxing-journal-1.7.5.apk'
          size = 6
          digest = 'sha256:' + (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
        })
      }
    }
  }
  function Case([string]$Name, [hashtable]$Change = @{}, [string[]]$Remove = @(),
      [string]$Reject = '', [scriptblock]$Setup = {}, [scriptblock]$Check = {}) {
    $testLog = Join-Path $root ([guid]::NewGuid().ToString('N') + '.log')
    $out = Join-Path $root ([guid]::NewGuid().ToString('N') + '.json')
    $badging = "package: name='com.example.studyassistant.journal' versionCode='57' versionName='1.7.5'"
    $signerOutput = "Signer #1 certificate SHA-256 digest: $cert"
    $aaptExit = 0; $signerExit = 0
    $evidence = New-Evidence
    $p = @{
      ApkPath = $apk; VersionName = '1.7.5'; VersionCode = 57; Channel = 'manual'
      PreviousVersionName = '1.7.4'; PreviousVersionCode = 56
      ApkUrl = 'https://mirror.example.test/release.apk'; OutPath = $out
      AaptPath = $aapt; ApkSignerPath = $signer
    }
    foreach ($key in $Remove) { $p.Remove($key) }
    foreach ($key in $Change.Keys) { $p[$key] = $Change[$key] }
    try {
      . $Setup
      [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 10), $utf8)
      $originalOutput = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out) } else { $null }
      $caught = $null; $messages = @()
      try { $messages = @(& $target @p) } catch { $caught = $_ }
      if ($Reject) {
        Assert ($null -ne $caught) 'Expected rejection, but script succeeded.'
        Assert ($caught.Exception.Message -match $Reject) ('Unexpected rejection: ' + $caught.Exception.Message)
        if ($null -ne $originalOutput) {
          Assert ([IO.File]::ReadAllText($out) -ceq $originalOutput) 'Rejected invocation changed existing output.'
        } else {
          Assert (-not (Test-Path -LiteralPath $out)) 'Rejected invocation wrote a manifest.'
        }
      } else {
        if ($caught) { throw $caught }
        $actualOut = if ($p.OutPath) { $p.OutPath } else { Join-Path $root 'update-stable.preflight.json' }
        $m = Get-Content -Raw -LiteralPath $actualOut | ConvertFrom-Json
        Assert ($m.versionCode -eq 57 -and $m.versionName -eq '1.7.5') 'Wrong version.'
        Assert ($m.applicationId -ceq 'com.example.studyassistant.journal') 'Wrong package.'
        Assert ($m.size -eq 6) 'Wrong size.'
        Assert ($m.sha256 -ceq (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()) 'Wrong hash.'
        $raw = [IO.File]::ReadAllBytes($actualOut)
        Assert ($raw[0] -eq 123) 'Output has BOM or is not a JSON object.'
        $calls = @(Get-Content -LiteralPath $testLog)
        Assert ($calls.Count -eq 2) 'Expected both Android tools exactly once.'
        Assert ($calls[0] -ceq "aapt|dump|badging|$apk") 'Incorrect aapt arguments.'
        Assert ($calls[1] -ceq "apksigner|verify|--verbose|--print-certs|$apk") 'Incorrect apksigner arguments.'
        . $Check
      }
      $script:passed++
      Write-Output "PASS $Name"
    } catch {
      $script:failed++
      Write-Output ("FAIL $Name : " + $_.Exception.Message)
    }
  }
  Case 'explicit APK URL' @{} @() '' {} { Assert ($m.apkUrl -ceq $p.ApkUrl) 'Explicit URL changed.' }
  Case 'legacy BaseUrl' @{ BaseUrl = 'https://mirror.example.test/updates/' } @('ApkUrl') '' {} {
    Assert ($m.apkUrl -ceq 'https://mirror.example.test/updates/1.7.5-57/chaoxing-journal-1.7.5-57.apk') 'Legacy URL changed.'
  }
  Case 'no URL' @{} @('ApkUrl') 'exactly one'
  Case 'conflicting URLs' @{ BaseUrl = 'https://mirror.example.test' } @() 'exactly one'
  foreach ($bad in @('http://example.test/a.apk', 'https://user:secret@example.test/a.apk', 'relative.apk', 'https://example.test/a#fragment', ' https://example.test/a', 'https://example.test\a')) {
    Case 'reject invalid APK URL' @{ ApkUrl = $bad } @() 'ApkUrl must'
  }
  foreach ($bad in @('http://example.test', 'https://u:p@example.test', 'https://example.test/?q=1')) {
    Case 'reject invalid base URL' @{ BaseUrl = $bad } @('ApkUrl') 'BaseUrl must'
  }
  Case 'backup URL preserved' @{ BackupApkUrl = 'https://backup.example.test/a.apk' } @() '' {} {
    Assert ($m.backupApkUrl -ceq $p.BackupApkUrl) 'Backup missing.'
  }
  Case 'reject HTTP backup' @{ BackupApkUrl = 'http://backup.example.test/a.apk' } @() 'BackupApkUrl must'
  Case 'reject credential backup' @{ BackupApkUrl = 'https://u:p@backup.example.test/a.apk' } @() 'BackupApkUrl must'
  Case 'previous name required' @{} @('PreviousVersionName') 'required'
  Case 'previous code required' @{} @('PreviousVersionCode') 'required'
  Case 'code must increase' @{ PreviousVersionCode = 57 } @() 'greater than'
  Case 'version cannot decrease' @{ PreviousVersionName = '1.7.6' } @() 'backwards'
  Case 'stable rejects patch' @{ Channel = 'stable' } @() 'major or minor'
  Case 'stable accepts minor' @{ Channel = 'stable'; PreviousVersionName = '1.6.99' }
  Case 'stable accepts major' @{ Channel = 'stable'; PreviousVersionName = '0.99.99' }
  Case 'invalid current version' @{ VersionName = '1.7' } @() 'three numeric'
  Case 'invalid previous version' @{ PreviousVersionName = '1.7' } @() 'three numeric'
  Case 'invalid version code' @{ VersionCode = 0 } @() 'positive'
  Case 'fixed application ID' @{ ApplicationId = 'another.package' } @() 'exactly match'
  Case 'fixed signer cannot be overridden' @{ ExpectedSignerSha256 = ('a' * 64) } @() 'must remain'
  Case 'aapt package mismatch' @{} @() 'applicationId' { $badging = $badging.Replace('studyassistant.journal', 'studyassistant.other') }
  Case 'aapt code mismatch' @{} @() 'versionCode' { $badging = $badging.Replace("'57'", "'58'") }
  Case 'aapt name mismatch' @{} @() 'versionName' { $badging = $badging.Replace('1.7.5', '1.7.6') }
  Case 'unparseable aapt output' @{} @() 'Could not parse' { $badging = 'not a package' }
  Case 'aapt failure despite plausible output' @{} @() 'aapt failed' { $aaptExit = 1 }
  Case 'apksigner failure despite plausible output' @{} @() 'apksigner rejected' { $signerExit = 1 }
  Case 'wrong certificate' @{} @() 'signer does not match' { $signerOutput = 'Signer #1 certificate SHA-256 digest: aaaa' }
  Case 'missing certificate' @{} @() 'signer does not match' { $signerOutput = 'Verified' }
  Case 'missing APK' @{ ApkPath = (Join-Path $root 'missing.apk') } @() 'does not exist|Cannot find'
  $invalid = Join-Path $root 'invalid.apk'
  [IO.File]::WriteAllBytes($invalid, [byte[]](1, 2, 3))
  Case 'invalid ZIP prefix' @{ ApkPath = $invalid } @() 'ZIP signature'
  Case 'directory is not APK' @{ ApkPath = $root } @() 'extension'
  Case 'missing aapt executable' @{ AaptPath = (Join-Path $root 'missing.exe') } @() 'does not exist|Cannot find'
  Case 'output cannot overwrite APK' @{ OutPath = $apk } @() 'overwrite the APK'
  $init = @{ InitializeStableBaselinePreflight = $true; Channel = 'stable'; VerifiedLatestEvidencePath = $evidencePath; StableEntryPath = $stable }
  $noPrevious = @('PreviousVersionName', 'PreviousVersionCode')
  Case 'baseline local preflight only' $init $noPrevious '' {} {
    Assert (-not (Test-Path -LiteralPath $stable)) 'Stable entry was written.'
    Assert (($messages -join "`n") -match 'initialization is NOT complete') 'Missing offline warning.'
  }
  Case 'baseline default candidate filename' $init ($noPrevious + @('OutPath'))
  Case 'baseline cannot take previous version' $init @() 'forbids PreviousVersion'
  $manualInit = $init.Clone(); $manualInit.Channel = 'manual'
  Case 'baseline cannot be manual' $manualInit $noPrevious 'requires stable'
  Case 'evidence forbidden in normal mode' @{ VerifiedLatestEvidencePath = $evidencePath } @() 'require Initialize'
  Case 'baseline evidence required' @{ InitializeStableBaselinePreflight = $true; Channel = 'stable'; StableEntryPath = $stable } $noPrevious 'requires Verified'
  Case 'baseline unverified evidence' $init $noPrevious 'maintainer-verified' { $evidence.verified = $false }
  Case 'baseline stale evidence' $init $noPrevious 'maintainer-verified' { $evidence.verifiedAtUtc = [DateTimeOffset]::UtcNow.AddDays(-2).ToString('o') }
  Case 'baseline future evidence' $init $noPrevious 'maintainer-verified' { $evidence.verifiedAtUtc = [DateTimeOffset]::UtcNow.AddDays(1).ToString('o') }
  Case 'baseline wrong evidence source' $init $noPrevious 'maintainer-verified' { $evidence.sourceUrl = 'https://example.test/latest' }
  Case 'baseline evidence version code mismatch' $init $noPrevious 'maintainer-verified' { $evidence.versionCode = 56 }
  Case 'baseline wrong latest tag' $init $noPrevious 'published' { $evidence.release.tag_name = 'v1.7.4' }
  Case 'baseline draft rejected' $init $noPrevious 'published' { $evidence.release.draft = $true }
  Case 'baseline prerelease rejected' $init $noPrevious 'published' { $evidence.release.prerelease = $true }
  Case 'baseline missing published date' $init $noPrevious 'published' { $evidence.release.published_at = '' }
  Case 'baseline wrong release origin' $init $noPrevious 'published' { $evidence.release.html_url = 'https://example.test/release' }
  Case 'baseline missing asset' $init $noPrevious 'APK bytes' { $evidence.release.assets = @() }
  Case 'baseline duplicate asset' $init $noPrevious 'APK bytes' { $evidence.release.assets = @($evidence.release.assets[0], $evidence.release.assets[0]) }
  Case 'baseline wrong asset route' $init $noPrevious 'APK bytes' { $evidence.release.assets[0].browser_download_url = 'https://example.test/a.apk' }
  Case 'baseline wrong digest' $init $noPrevious 'APK bytes' { $evidence.release.assets[0].digest = 'sha256:' + ('a' * 64) }
  Case 'baseline wrong size' $init $noPrevious 'APK bytes' { $evidence.release.assets[0].size = 7 }
  Case 'baseline output cannot be stable entry' $init $noPrevious 'must not overwrite' { $p.OutPath = $stable }
  Case 'baseline output cannot be evidence' $init $noPrevious 'must not overwrite' { $p.OutPath = $evidencePath }
  Case 'baseline refuses existing candidate' $init $noPrevious 'already exists' { [IO.File]::WriteAllText($out, 'keep') }
  # Existing output is deliberately preserved; its rejection check is separate.
  [IO.File]::WriteAllText($stable, 'existing stable')
  Case 'baseline refuses existing stable entry' $init $noPrevious 'already exists'
  Assert ((Get-Content -Raw -LiteralPath $stable) -ceq 'existing stable') 'Existing stable entry changed.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Output "RESULT: $passed passed, $failed failed (synthetic offline PowerShell tests)."
if ($failed -gt 0) { exit 1 }
