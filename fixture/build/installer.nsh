!macro customInstall
  ; Chrome/Firefox-*inspired* ACL loosening -- see README.md for why this is NOT
  ; actually what Chrome/Firefox do (they run a standing privileged service instead).
  ; This grants the built-in Users group (SID S-1-5-32-545, locale-independent) Modify
  ; rights on the install directory, recursively, so a later silent update apply -- once
  ; paired with electron-userland/electron-builder#10085's registry+directory
  ; writability check -- can skip re-elevating. Runs at the end of the install section,
  ; which for a Program Files target is already running elevated.
  DetailPrint "Granting Users modify rights on $INSTDIR"
  nsExec::ExecToLog 'icacls "$INSTDIR" /grant *S-1-5-32-545:(OI)(CI)M /T'
!macroend
