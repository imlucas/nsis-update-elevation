# nsis-update-elevation

A from-scratch, scripted reproduction rig for two findings about Electron auto-updates on
Windows:

1. **electron-updater's differential ("delta") download needs a genuine multi-range HTTP
   server**, not just single-range support — the naive check most people use to verify
   this (`curl -r 0-99 -> 206`) passes on servers that will never actually save any bytes.
2. **electron-builder's NSIS installer re-elevates on every silent update apply**, driven
   by a persisted registry flag rather than a live check of whether elevation is actually
   still needed — and the obvious fix (check if the install directory is writable) has a
   real corruption bug, fixed by a draft patch:
   [electron-userland/electron-builder#10085](https://github.com/electron-userland/electron-builder/pull/10085).

Everything here is designed to be re-run by hand on a real Windows machine — an admin
account, with a few unavoidable manual steps (running an installer, clicking a UAC
prompt) that no script can perform for you by design.

## Layout

```
fixture/                  minimal Electron app (like a stripped-down "DiffUpd")
  package.json main.js eb.yml
  build/installer.nsh              customInstall hook: loosens the install dir's file ACL
  build/installer-full-loosen.nsh  same, + loosens the registry key ACL too (see caveat below)
server/
  differential-update-test-server.mjs   the fix: real RFC 7233 multipart/byteranges support
  single-range-test-server.mjs          the failure mode: single-range only, like http-server
scripts/                   PowerShell, see each script's comment-based help (Get-Help -Full)
  Build-ElectronBuilder.ps1  clones + compiles electron-builder from source at an exact commit
  Build-Version.ps1
  Start-UpdateServer.ps1
  Test-InstallAcl.ps1
  Get-DiffUpdVersion.ps1
  Invoke-FullRepro.ps1     guided top-level walkthrough of everything below
```

Every build in this repo goes through electron-builder compiled from source at an exact
pinned commit — no packaged binary shortcut anywhere — so any two builds you compare
differ by exactly the commits you chose between them, and nothing else.

## Finding 1: differential downloads need multi-range support

electron-updater's differential downloader
([`multipleRangeDownloader.ts`](https://github.com/electron-userland/electron-builder/blob/master/packages/electron-updater/src/differentialDownloader/multipleRangeDownloader.ts))
sends a single request naming *multiple* byte ranges (`Range: bytes=a-b, c-d, ...`) and
requires the server to answer with one genuine
[RFC 7233 §4.1 `multipart/byteranges`](https://www.rfc-editor.org/rfc/rfc7233.html#section-4.1)
response. A server that only implements single-range requests — which is what `npx
http-server` does, and what most CDNs/object storage support out of the box — passes the
common smoke test (`curl -r 0-99 ... -> 206`) but will make electron-updater log:

```
Cannot download differentially, fallback to full download: Error: Content-Type "multipart/byteranges" is expected, but got "null"
```

on every update, silently downloading the full installer every time. This is a
well-known, previously-reported gap on electron-builder's own issue tracker:
[#5758](https://github.com/electron-userland/electron-builder/issues/5758),
[#3742](https://github.com/electron-userland/electron-builder/issues/3742),
[#7161](https://github.com/electron-userland/electron-builder/issues/7161).

`server/differential-update-test-server.mjs` implements the multi-range case correctly —
verified against a real fixture app, it produced real savings of ~0.8–1% of the full
installer size across several version hops.

Reproduce the failure, then the fix:

```powershell
.\scripts\Build-ElectronBuilder.ps1 -Branch c0b8235d7f86d90ffe7218765115b6948b180739
$builder = '.\electron-builder\packages\electron-builder\cli.js'   # path it printed

.\scripts\Build-Version.ps1 -Version 1.0.0 -BuilderCommand $builder
.\scripts\Build-Version.ps1 -Version 1.0.1 -BuilderCommand $builder
.\scripts\Start-UpdateServer.ps1 -Variant SingleRange
# install 1.0.0 (redirect to C:\Program Files\DiffUpd), then launch it -> full download,
# not differential, even though the naive curl -r check would have passed.

.\scripts\Build-Version.ps1 -Version 1.0.2 -BuilderCommand $builder
.\scripts\Start-UpdateServer.ps1 -Variant MultiRange
# launch the app again -> genuinely differential this time; check the server's job log.
```

## Finding 2: elevation is a registry flag, not a live check — and the naive fix corrupts state

### The mechanism

For a `perMachine: false` NSIS installer redirected outside its default per-user
location (via `allowToChangeInstallationDirectory`, e.g. to `C:\Program Files`), every
subsequent **silent** update apply unconditionally re-elevates. Traced to source:

- [`installer.nsi`'s `Section "install"`](https://github.com/electron-userland/electron-builder/blob/c0b8235d7f86d90ffe7218765115b6948b180739/packages/app-builder-lib/templates/nsis/installer.nsi#L94-L124)
  elevates whenever `$hasPerMachineInstallation == "1"` and the run is silent.
- That flag is set once, in
  [`initMultiUser`](https://github.com/electron-userland/electron-builder/blob/c0b8235d7f86d90ffe7218765115b6948b180739/packages/app-builder-lib/templates/nsis/assistedInstaller.nsh#L107-L120),
  purely by reading `HKLM\Software\<APP_GUID>\InstallLocation` — a value written once
  during the original elevated install and never re-checked against reality.
- electron-updater's own JS
  ([`NsisUpdater.ts`'s `doInstall`](https://github.com/electron-userland/electron-builder/blob/master/packages/electron-updater/src/NsisUpdater.ts))
  tries an *unelevated* spawn first and only falls back to `elevate.exe` on a spawn
  error — so the UAC prompt observed here is coming from inside the NSIS script itself,
  not from electron-updater deciding to elevate.

### The corruption bug

The obvious fix — skip elevation if `$INSTDIR` is actually writable (e.g. because a
`customInstall` hook already loosened its ACL) — looks complete: no prompt, install
succeeds. It isn't complete. The install section *also* writes the per-machine
registration
([`registryAddInstallInfo`](https://github.com/electron-userland/electron-builder/blob/c0b8235d7f86d90ffe7218765115b6948b180739/packages/app-builder-lib/templates/nsis/include/installer.nsh#L103-L105))
to `HKLM` via a plain `WriteRegStr`, which **fails silently** — no error, no abort — when
unelevated. Skipping elevation on a directory-only check lets the file copy succeed while
quietly wiping the `InstallLocation` value the *next* launch's `initMultiUser` depends
on. Confirmed directly: `HKLM:\Software\<APP_GUID>\InstallLocation` went from a correct
path to empty after one unelevated apply, and the next update defaulted to a fresh
per-user install at the wrong path instead of finding the existing one.

The fix in
[electron-userland/electron-builder#10085](https://github.com/electron-userland/electron-builder/pull/10085)
adds a second, registry-writability probe alongside the directory one, and only skips
elevation when *both* hold.

### It is *not* "the Chrome/Firefox pattern" (correcting an earlier draft of this work)

An earlier version of the PR description and its code comments called ACL-loosening
"the Chrome/Firefox pattern." That conflated two genuinely different techniques, and
this repo exists partly to set the record straight with real citations instead of
leaving the wrong one standing:

- **Firefox** ships a Windows service, the **Mozilla Maintenance Service**, installed
  once with elevation. Its *service* ACL — not the install directory's file ACL — is
  modified so a non-elevated process can start/stop it (`SERVICE_START` granted to
  authenticated users); the service itself, running with sufficient rights, performs the
  write on the user's behalf.
  - [Mozilla Support — "What is the Mozilla Maintenance Service?"](https://support.mozilla.org/en-US/kb/what-mozilla-maintenance-service)
  - [MozillaWiki — Windows Service Silent Update](https://wiki.mozilla.org/Windows_Service_Silent_Update#Service_installation)
  - [Bugzilla 481815 — original service proposal](https://bugzilla.mozilla.org/show_bug.cgi?id=481815)
- **Chrome** uses **Google Update (Omaha)**. For a system-level install, the actual
  update task runs under the **LocalSystem** account, not the interactive user's token —
  there's nothing for the interactive user to elevate in the first place.
  - [google/omaha](https://github.com/google/omaha)
  - [Omaha 3 walkthrough](https://github.com/google/omaha/blob/main/doc/Omaha3Walkthrough.md)

Both are a **standing privileged service** pattern: a separate, persistently-elevated
process does the write, rather than loosening file/registry permissions on the
interactive user's own token. That's a heavier but more thorough answer than what this
repo tests — it also covers a registry key an app never loosens, which is exactly the
gap `#10085` had to patch around instead. `build/installer.nsh` and the
`IsDirWritable`/`IsRegKeyWritable` checks are a narrower, service-free alternative for
apps that would rather not ship one.

### NSIS elevation mechanics, for reference

The self-elevation relaunch (`UAC_RunElevated`) used throughout electron-builder's NSIS
templates comes from the community `UAC` plugin:
[tpn/nsis-uac](https://github.com/tpn/nsis-uac),
[NSIS wiki page](https://nsis.sourceforge.io/UAC_plug-in).

### Reproducing the electron-builder patch

This is the long path — it involves building electron-builder from source, and needs a
registry cleanup step between attempts because a partial/corrupted state from one test
will confuse the next one. Budget for several UAC-click round trips.

```powershell
.\scripts\Build-ElectronBuilder.ps1 -Destination .\eb-patched -Branch nsis-skip-unnecessary-elevation -Remote https://github.com/imlucas/electron-builder.git
$builder = '.\eb-patched\packages\electron-builder\cli.js'   # path it printed

# 1. Fresh install through the PATCHED builder + the ACL-loosening hook (build/installer.nsh
#    is already wired into fixture\eb.yml's nsis.include), so identities/GUIDs stay
#    consistent between the patched builder's own builds. Bump to a fresh version:
.\scripts\Build-Version.ps1 -Version 1.0.20 -BuilderCommand $builder
# Run fixture\dist\DiffUpd Setup 1.0.20.exe DIRECTLY (not the installed app), redirect to
# C:\Program Files\DiffUpd. Approve UAC -- this is the one unavoidable elevated install.

.\scripts\Test-InstallAcl.ps1 -AppGuid <guid-from-HKLM-Software>
# Confirms dirWritable=1 (the customInstall hook loosened the file ACL) and, since this
# repo's build/installer.nsh does NOT also loosen the registry key,  regWritable=0.

.\scripts\Build-Version.ps1 -Version 1.0.21 -BuilderCommand $builder
.\scripts\Start-UpdateServer.ps1
# Launch C:\Program Files\DiffUpd\DiffUpd.exe (now 1.0.20). Expect: UAC still fires.
# That's correct, safe behavior -- the registry probe correctly caught what the
# directory-only check would have missed, and fell back to elevating exactly like
# upstream. No corruption.
```

To see the *other* branch — a directory-only check silently corrupting the registry —
temporarily revert `installer.nsi`'s `${orIf} $R8 == "0"` line in the patched clone (or
check out the parent commit of `0b5c6c9` on the `nsis-skip-unnecessary-elevation`
branch) and repeat. `Test-InstallAcl.ps1 -AppGuid ...` before/after will show
`InstallLocation` go from a correct path to empty.

## What's verified vs. not

Being precise about this matters more than looking complete:

- **Verified live, this session:** the single-range failure mode; the multi-range fix
  and its byte savings; the wizard-then-UAC-on-interaction sequence; `isSilent: true`
  dropping the wizard but not the prompt; the ACL-loosening-alone corruption bug; the
  two-way check correctly falling back to elevation when only the directory ACL (not the
  registry) was loosened.
- **Not independently re-verified live:** `build/installer-full-loosen.nsh` (the variant
  that *also* loosens the registry key ACL, which by construction of the check should let
  a patched build skip elevation with no corruption) — the registry-ACL-loosening half of
  that combination wasn't exercised in the same test pass as the rest. If you run it and
  it doesn't work as described, that's real information — please report back rather than
  assuming the write-up is stale.
- [electron-userland/electron-builder#10085](https://github.com/electron-userland/electron-builder/pull/10085) —
  the draft upstream patch.
