@echo off
rem QS77, QS393: what a release ships. The client published self-contained and ReadyToRun, signed,
rem packed into one Setup.exe (Inno Setup, tools\installer\aduzi.iss), and SHA256SUMS.txt beside it.
rem
rem   release.cmd -Certificate <thumbprint>
rem   release.cmd -Unsigned
rem
rem A release is signed, so without a certificate it refuses unless -Unsigned is given - and then the
rem setup is named ...-setup-unsigned.exe, which is how an unsigned build cannot pass for a release.
rem
rem The performance gate is optional: with -Gated the published build is timed by run-perf-gate.cmd's
rem gate against this machine's baseline, and a regression nothing explained refuses it (QS79).
rem
rem The setup and its checksum land in artifacts\release\. Needs Inno Setup 6: winget install JRSoftware.InnoSetup.
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\release.ps1" %*
exit /b %ERRORLEVEL%
