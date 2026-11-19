# Installing

Aduzi ships as one installer, `aduzi-<version>-win-x64-setup.exe`, with `SHA256SUMS.txt` beside
it. It needs Windows 10 or 11 on x64 and nothing else — the .NET runtime is inside the installer.

Check a download against the sums before running it:

```
certutil -hashfile aduzi-0.2.1-win-x64-setup.exe SHA256
```

**The installer is not signed yet**, so SmartScreen warns when it starts: *More info*, then *Run
anyway*. Signing is owed before the first release rather than after it, and until it lands a build
says so in its own name: `...-setup-unsigned.exe`.

## Install it with Setup

Run the setup. In English or Portuguese, following Windows, it:

1. asks whether to install for you or for every user of the computer — for you needs no
   administrator;
2. says what it installs and where, and that your settings survive an upgrade and an uninstall;
3. installs, then shows the first steps: importing sessions, the command palette;
4. offers to start Aduzi.

If Aduzi is open, Setup says so and waits for it to be closed: an open session would lose what it
was doing. For a deployment, the same setup runs silently:

```
aduzi-0.2.1-win-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /CURRENTUSER
aduzi-0.2.1-win-x64-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /ALLUSERS
```

Its exit code is the client's own (the table at the end): `740` when every user was asked for
without an administrator.

Setup is a front for the install described below — it runs `aduzi.exe --install` from the files it
carries — so Setup adds no uninstaller of its own, and **Installed apps** removes Aduzi the same way
whichever way it was installed.

## Run it without installing

Copy an installed `Aduzi` folder anywhere — a USB stick, another drive — and put an empty file named
`aduzi.portable` beside `aduzi.exe`. That copy is **portable**: it keeps its settings, saved
sessions and logs in `data\` next to it, and nothing is written to your profile. Deleting the
folder removes all of it.

## Keep the files somewhere else

Set `ADUZI_DATA` to a folder and that launch keeps its settings, saved sessions and logs
there, whichever copy it is: a second profile beside your usual one, or a store on another drive.
It wins over `aduzi.portable` and over `%AppData%`, and installing or uninstalling never
touches the folder it names.

## Install it for yourself from a copy

From a portable copy, open the palette with `Ctrl+Shift+P` and choose **Install Aduzi for this
user**, or run:

```
aduzi.exe --install
```

There is no administrator prompt. The program goes to `%LocalAppData%\Programs\Aduzi`,
Aduzi appears in your Start menu, and it is listed under **Installed apps** in Settings.

- The installed copy keeps its settings in `%AppData%\Aduzi`. The copy you installed from keeps
  its own in its `data` folder, and still works.
- Installing a newer version, with Setup or this way, replaces the installed copy whole — nothing of the old
  version is left beside the new one.
- If the installed copy is running, you are asked to close it first rather than getting half of
  each version.

## Install it for every user

For a managed deployment, from an elevated prompt:

```
aduzi.exe --install --all-users --quiet
```

That is `C:\Program Files\Aduzi`, every user's Start menu, and an entry under
`HKEY_LOCAL_MACHINE`. Asked without an administrator, it exits with 740 — *the requested operation
requires elevation* — which is the code deployment tools already read that way. Without `--quiet` it
asks Windows for the administrator instead.

## Upgrading from quickshell

Aduzi was called quickshell until November 2026. Installing Aduzi over a quickshell install
removes the old program folder, its Start menu shortcut and its entry, so one app is listed and
not two. The first start then moves `%AppData%\quickshell` to `%AppData%\Aduzi`, with every
setting, saved session and key in it. If an old copy is still running and holds that folder, the
new one uses it where it is and moves it on a later start.

The old names still work: a portable copy with `quickshell.portable` beside it stays portable,
and `QUICKSHELL_DATA` is read when `ADUZI_DATA` is not set.

## Uninstall it

From **Installed apps** in Settings, or `aduzi.exe --uninstall` from the installed copy. It
removes the program folder, the Start menu shortcut and the entry, and then asks whether to remove
your settings and saved sessions too — they are kept unless you say yes, so a later install finds
them. `--uninstall --quiet`, which is what a deployment runs, never removes them.

## What it does to your machine, all of it

- A folder of program files, a Start menu shortcut, and one entry in the list of installed apps.
- No service, no scheduled task, no file association, no change to `PATH`.
- It does not check for updates yet.

## Build it from source

The .NET SDK that `global.json` names (10.0.404 today, or a later 10.0.4xx patch) on Windows x64 is
the only prerequisite. It is pinned because its patch decides the .NET runtime a release ships, which
`THIRD-PARTY-NOTICES.md` lists at that version. Clone, then from the repository root:

```
run-tests.cmd
```

That restores, builds the solution and runs every test, and its exit code is the verdict. A fresh
clone has been built and passed this way with an empty NuGet cache, and in a separate Windows guest
from the committed tree alone, with no other step (QS90). The SSH tests skip unless their fixture is
running — `prototypes/SshProbe/fixture/up.sh` says how. `release.cmd` builds what a release ships.

To use what you built, `run.cmd` builds the client alone and starts it: `run.cmd Release` for the
configuration CI tests, and anything after it goes to `aduzi.exe`, as in
`run.cmd Release --session prod`. With no configuration named it builds Debug.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Done. |
| `1` | Not done. Without `--quiet` a dialog said why. |
| `740` | Installing or removing it for every user needs an administrator. |
