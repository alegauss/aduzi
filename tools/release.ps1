#Requires -Version 5.1
<#
.SYNOPSIS
  Build what a release ships: the client published self-contained and signed, packed into one
  Setup.exe wizard that installs it (QS393), and the checksum a download is checked against.

.DESCRIPTION
  QS77, QS393. One Setup.exe. Its wizard says what it installs and where, then runs the build's own
  `aduzi --install` from a temporary folder - for the person running it with no administrator
  prompt, or for every user when they chose that - so a release installs through the same code as
  the palette's "Install Aduzi for this user" and is removed by the entry that code writes.

  The build is the one QS75 measured - Release, self-contained, ReadyToRun - so the start-up figure
  in benchmarks\results\startup-h.md is a figure about the thing people download.

  It does not ship unsigned by accident. Signing is part of making a release rather than a later
  improvement: an unsigned binary is refused by SmartScreen and by corporate policy, which for a
  client that handles credentials is the worst first impression on offer. So with a certificate it
  signs and refuses a signature this machine does not verify, and without one it refuses to run
  unless -Unsigned says so - and then the setup's own name says so too, where nobody can miss it.

  With -Gated it does not ship a regression by accident (QS79). Once the client is published, the
  performance gate times that build's start, and the parse and emulate arms of the replay harness
  run on that build's own assemblies and runtime settings, against this machine's baseline. A figure worse than the baseline's
  own noise allows refuses the release before anything is signed or packed. So does one a commit
  since the baseline said was meant: that trade is allowed, and a new baseline is owed before the
  release, or the trailer would go on excusing the figure by any amount. A machine with no baseline
  is refused too. The gate is optional, by the maintainer's call: without -Gated the run says
  UNGATED where it would have printed the verdict.

.PARAMETER Certificate
  The thumbprint of a code-signing certificate in the current user's store. Its private key may be
  on a token; signtool asks the token for its PIN itself.

.PARAMETER Timestamp
  An RFC 3161 timestamp server. A signature without a timestamp dies with its certificate; one with
  a timestamp stays valid for what was signed while the certificate was.

.PARAMETER Unsigned
  Build without signing. The setup is named ...-setup-unsigned.exe, so it cannot pass for a release.

.PARAMETER Gated
  Run the performance gate on the published build before signing it, on a machine that has a
  baseline.

.PARAMETER Output
  Where the setup and SHA256SUMS.txt go: artifacts\release unless given, which .gitignore covers.
#>
[CmdletBinding()]
param(
    [string] $Certificate,

    [string] $Timestamp = 'http://timestamp.digicert.com',

    [switch] $Unsigned,

    [switch] $Gated,

    [string] $Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root 'src\Quickshell.App\Quickshell.App.csproj'
$publish = Join-Path $root 'artifacts\publish\aduzi'
if (-not $Output) { $Output = Join-Path $root 'artifacts\release' }

function Refuse {
    param([Parameter(Mandatory)] [string] $What, [string] $Remedy)
    Write-Host ''
    Write-Host "release: $What" -ForegroundColor Red
    if ($Remedy) { Write-Host "         -> $Remedy" -ForegroundColor Yellow }
    exit 3
}

function Find-SignTool {
    # The newest SDK's, because an older signtool may not know the digest a timestamp server answers
    # with. x64 and never arm or x86: this is the machine the release is built on.
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kits) {
        $found = Get-ChildItem -LiteralPath $kits -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version] $_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($found) { return $found }
    }
    $onPath = Get-Command 'signtool.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

function Find-Iscc {
    # Inno Setup's compiler (QS393): per-user where winget puts it, machine-wide where GitHub's
    # windows runner has it, or on PATH.
    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'))) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    $onPath = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

if (-not $Certificate -and -not $Unsigned) {
    Refuse 'a release is signed, and no certificate was given' 'Pass -Certificate <thumbprint>, or -Unsigned for a build whose name says it is not a release.'
}
if ($Certificate -and $Unsigned) {
    Refuse '-Certificate and -Unsigned were both given' 'A build is one or the other.'
}

$signtool = $null
if ($Certificate) {
    # Asked before a two-minute publish rather than after it.
    $signtool = Find-SignTool
    if (-not $signtool) { Refuse 'signtool.exe was not found' 'Install the signing tools of the Windows SDK.' }
    if (-not (Test-Path -LiteralPath "Cert:\CurrentUser\My\$Certificate")) {
        Refuse "no certificate with the thumbprint $Certificate is in the current user's store" 'certmgr.msc shows what is there, under Personal.'
    }
}

# Asked before the two-minute publish rather than after it: a release is the setup.
$iscc = Find-Iscc
if (-not $iscc) { Refuse 'Inno Setup''s compiler (ISCC.exe) was not found' 'winget install JRSoftware.InnoSetup' }

$version = (& dotnet msbuild $project -nologo -getProperty:Version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $version) { Refuse 'the version could not be read from the project' }

Write-Host "release  Aduzi $version" -ForegroundColor Cyan

# Wiped, never published over: a file the last build had and this one does not would otherwise ride
# into the archive as part of a version it is not.
if (Test-Path -LiteralPath $publish) { Remove-Item -LiteralPath $publish -Recurse -Force }

& dotnet publish $project --configuration Release --runtime win-x64 --self-contained true `
    -p:PublishReadyToRun=true --output $publish --nologo -v quiet
if ($LASTEXITCODE -ne 0) { Refuse 'the publish failed' }

# Before the gate's ten minutes: the notices are the claim that every shipped component is
# OSI-licensed, and it is read against what this publish resolved (QS378).
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-notices.ps1') `
    -Deps (Join-Path $publish 'aduzi.deps.json') -Notices (Join-Path $root 'THIRD-PARTY-NOTICES.md')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $Gated) {
    Write-Host '  UNGATED    the performance gate was not run on this build; -Gated runs it' -ForegroundColor Yellow
}
else {
    # The build just published, timed where it lies: the start the gate measures is the start of the
    # archive about to be made, before a marker or a signature is added to it. Built first and on its
    # own, because a gate that did not compile has judged nothing, and `dotnet run` would hand that
    # back as the exit code that means a figure got worse.
    Write-Host '  gating     against this machine''s baseline'
    & dotnet build (Join-Path $root 'tools\Quickshell.Gate\Quickshell.Gate.csproj') -c Release --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { Refuse 'the performance gate did not build, so this build was not judged' }

    & (Join-Path $root 'tools\Quickshell.Gate\bin\Release\net10.0-windows\Quickshell.Gate.exe') `
        --client (Join-Path $publish 'aduzi.exe')
    switch ($LASTEXITCODE) {
        0 { }
        1 { Refuse 'the performance gate found a figure worse than its baseline allows' 'Find what cost it, or say in the commit that made it: Performance-Moved: <figure> - <what it bought>.' }
        2 { Refuse 'a commit since the baseline traded a figure, and no baseline has been taken since' 'Take one at this commit with run-perf-gate.cmd --baseline, commit it, and release again.' }
        default { Refuse 'the performance gate could not judge this build' 'What it printed above says why; without -Gated the build skips it, and says so.' }
    }
}

if ($Certificate) {
    # This client's own files. The runtime's are Microsoft's, already signed by Microsoft.
    $ours = @(Get-ChildItem -LiteralPath $publish -File |
        Where-Object { $_.Name -eq 'aduzi.exe' -or $_.Name -like 'Quickshell.*.dll' })

    & $signtool sign /sha1 $Certificate /fd sha256 /tr $Timestamp /td sha256 /q @($ours | ForEach-Object { $_.FullName })
    if ($LASTEXITCODE -ne 0) { Refuse 'signtool could not sign the build' }

    foreach ($file in $ours) {
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        if ($signature.Status -ne 'Valid') {
            Refuse "$($file.Name) is signed but does not verify: $($signature.StatusMessage)" 'A release is signed with a certificate this machine trusts, or it is not signed at all.'
        }
    }
    Write-Host "  signed     $($ours.Count) files, by $((Get-Item "Cert:\CurrentUser\My\$Certificate").Subject)"
}
else {
    Write-Host '  UNSIGNED   no certificate was given, and the setup is named for it' -ForegroundColor Yellow
}

# The licence and the bundled libraries' notices, which MIT and ISC ask to travel with every copy (QS285).
foreach ($notice in @('LICENSE', 'THIRD-PARTY-NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $root $notice) -Destination $publish -Force
}

$suffix = if ($Unsigned) { '-unsigned' } else { '' }
$null = New-Item -ItemType Directory -Path $Output -Force

# What an earlier build of this version left here - the zip a release shipped before QS393, a setup -
# so the folder holds what this build made. Other versions' files stay: install-vm -Former installs one.
Get-ChildItem -LiteralPath $Output -File |
    Where-Object { $_.Name -like "aduzi-$version-win-x64*" -or $_.Name -eq 'SHA256SUMS.txt' } |
    Remove-Item -Force

# QS393. A release is one Setup.exe, built from the signed files. Its wizard runs the build's own
# `aduzi.exe --install`, so it and the palette's install are one install, removed by one entry.
$setupBase = "aduzi-$version-win-x64-setup$suffix"
$setup = Join-Path $Output "$setupBase.exe"
& $iscc /Q "/DPayload=$publish" "/DAppVersion=$version" "/DOutputName=$setupBase" "/DOutputDir=$Output" `
    (Join-Path $PSScriptRoot 'installer\aduzi.iss')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $setup)) { Refuse 'Inno Setup could not build the setup' 'What ISCC printed above says why.' }

if ($Certificate) {
    & $signtool sign /sha1 $Certificate /fd sha256 /tr $Timestamp /td sha256 /q $setup
    if ($LASTEXITCODE -ne 0) { Refuse 'signtool could not sign the setup' }
    $signature = Get-AuthenticodeSignature -LiteralPath $setup
    if ($signature.Status -ne 'Valid') { Refuse "the setup is signed but does not verify: $($signature.StatusMessage)" }
}

# The line `sha256sum -c` reads, with a newline it reads too. From .NET and not Get-FileHash, which
# does not load in this Windows PowerShell when CI's pwsh step started it (QS266).
$stream = [IO.File]::OpenRead($setup)
try { $hash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($stream)) -replace '-', '').ToLowerInvariant() }
finally { $stream.Dispose() }
[IO.File]::WriteAllText((Join-Path $Output 'SHA256SUMS.txt'), "$hash  $setupBase.exe`n")

$files = @(Get-ChildItem -LiteralPath $publish -File -Recurse).Count
$unpacked = [math]::Round((Get-ChildItem -LiteralPath $publish -File -Recurse | Measure-Object Length -Sum).Sum / 1MB)
$packed = [math]::Round((Get-Item -LiteralPath $setup).Length / 1MB, 1)

Write-Host "  setup      $setup"
Write-Host "             $packed MB, $files files, $unpacked MB installed"
Write-Host "  sha256     $hash"
exit 0
