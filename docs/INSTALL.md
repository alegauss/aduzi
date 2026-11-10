# Installing

Aduzi ships as one archive, `aduzi-<version>-win-x64.zip`, with `SHA256SUMS.txt` beside
it. It needs Windows 10 or 11 on x64 and nothing else — the .NET runtime is inside the archive.

Check a download against the sums before running it:

```
certutil -hashfile aduzi-0.1.0-win-x64.zip SHA256
```

**The archive is not signed yet**, so SmartScreen warns on its first start. Signing is owed before
the first release rather than after it, and until it lands a build says so in its own name:
`...-unsigned.zip`.

## Run it without installing

Unzip it anywhere — Downloads, a USB stick — and start `aduzi.exe` in the folder it makes.

That copy is **portable**. The file `aduzi.portable` beside the executable keeps its settings,
saved sessions and logs in `data\` next to it, and nothing is written to your profile. Deleting the
folder removes all of it.

## Keep the files somewhere else

Set `ADUZI_DATA` to a folder and that launch keeps its settings, saved sessions and logs
there, whichever copy it is: a second profile beside your usual one, or a store on another drive.
It wins over `aduzi.portable` and over `%AppData%`, and installing or uninstalling never
touches the folder it names.

## Install it for yourself

From that copy, open the palette with `Ctrl+Shift+P` and choose **Install Aduzi for this
user**, or run:

```
aduzi.exe --install
```

There is no administrator prompt. The program goes to `%LocalAppData%\Programs\Aduzi`,
Aduzi appears in your Start menu, and it is listed under **Installed apps** in Settings.

- The installed copy keeps its settings in `%AppData%\Aduzi`. The copy you installed from keeps
  its own in its `data` folder, and still works.
- Installing a newer archive the same way replaces the installed copy whole — nothing of the old
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

The .NET 10 SDK on Windows x64 is the only prerequisite. Clone, then from the repository root:

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
