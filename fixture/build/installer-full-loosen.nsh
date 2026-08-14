!macro customInstall
  ; Extends installer.nsh with a registry-key ACL grant, so that a
  ; electron-builder#10085-patched build's IsRegKeyWritable check *also* passes and the
  ; silent apply can skip elevation with no risk of the corruption documented in
  ; README.md's "The corruption bug" section (registryAddInstallInfo's WriteRegStr to
  ; HKLM otherwise fails silently when unelevated).
  ;
  ; NOT independently re-verified live in the same session as the rest of this repo --
  ; see README.md "What's verified vs. not" before relying on this. Swap this file in for
  ; build/installer.nsh (update eb.yml's nsis.include) to exercise it.
  DetailPrint "Granting Users modify rights on $INSTDIR"
  nsExec::ExecToLog 'icacls "$INSTDIR" /grant *S-1-5-32-545:(OI)(CI)M /T'

  ; Note the doubled $$ before every PowerShell variable: NSIS performs its own $-prefixed
  ; substitution on strings (that's how $INSTDIR above gets filled in), so a literal
  ; PowerShell $k would either vanish or warn as an unrecognized NSIS variable. "$$"
  ; is NSIS's own escape for a literal "$".
  DetailPrint "Granting Users write rights on HKLM\${INSTALL_REGISTRY_KEY}"
  nsExec::ExecToLog `powershell -NoProfile -ExecutionPolicy Bypass -Command "$$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('${INSTALL_REGISTRY_KEY}', [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions); $$acl = $$k.GetAccessControl(); $$rule = New-Object System.Security.AccessControl.RegistryAccessRule('Users','FullControl','ContainerInherit','None','Allow'); $$acl.AddAccessRule($$rule); $$k.SetAccessControl($$acl); $$k.Close()"`
!macroend
