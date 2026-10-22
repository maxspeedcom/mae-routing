; MAE Routing for Windows — installer (built on Linux by build-windows.sh with makensis)
; Defines from the build: VERSION (1.104.2), BUILD, SRCDIR (binaries), ASSETS (icons/bitmaps), OUTFILE
Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
RequestExecutionLevel admin

!define APP      "MAE Routing"
!define SVC      "MAERouting"
!define EXE      "MAERouting.exe"
!define UNINST   "Software\Microsoft\Windows\CurrentVersion\Uninstall\MAERouting"
!define RUNKEY   "Software\Microsoft\Windows\CurrentVersion\Run"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\MAE Routing"
InstallDirRegKey HKLM "${UNINST}" "InstallLocation"
BrandingText "MAE Routing ${VERSION}-${BUILD} · routing.maesuaisystem.com"
VIProductVersion "${VERSION}.${BUILD}"
VIAddVersionKey /LANG=0 "ProductName" "${APP}"
VIAddVersionKey /LANG=0 "FileDescription" "MAE Routing Setup"
VIAddVersionKey /LANG=0 "CompanyName" "MAE Routing (maesuaisystem.com)"
VIAddVersionKey /LANG=0 "FileVersion" "${VERSION}.${BUILD}"
VIAddVersionKey /LANG=0 "ProductVersion" "${VERSION}.${BUILD}"
VIAddVersionKey /LANG=0 "LegalCopyright" "© 2026 MAE Routing"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!define MUI_ICON "${ASSETS}\MAERouting.ico"
!define MUI_UNICON "${ASSETS}\MAERouting.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "${ASSETS}\header.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${ASSETS}\wizard.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${ASSETS}\wizard.bmp"
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "ติดตั้ง MAE Routing"
!define MUI_WELCOMEPAGE_TEXT "MAE Routing เชื่อมคอมพิวเตอร์เครื่องนี้เข้ากับเครือข่ายส่วนตัวขององค์กรคุณ เข้ารหัสด้วย WireGuard ใช้ได้จากทุกที่$\r$\n$\r$\nหลังติดตั้ง ไอคอน MAE Routing จะอยู่ที่มุมขวาล่างของหน้าจอ คลิกแล้วเลือก “เข้าสู่ระบบ…” และใส่ชื่อเครือข่ายขององค์กร$\r$\n$\r$\nยังไม่มีเครือข่าย? สร้างฟรีที่ routing.maesuaisystem.com"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "ติดตั้ง MAE Routing เรียบร้อย"
!define MUI_FINISHPAGE_TEXT "คลิกไอคอน MAE Routing ที่มุมขวาล่างของหน้าจอ แล้วเลือก “เข้าสู่ระบบ…” เพื่อเชื่อมต่อเครือข่ายขององค์กร"
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "เปิด MAE Routing ตอนนี้"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchTray
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Thai"
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "MAE Routing รองรับ Windows 64 บิต (x64) เท่านั้น"
    Abort
  ${EndIf}
  SetRegView 64
FunctionEnd

Function LaunchTray
  ; via explorer.exe so the tray app runs as the signed-in user, not elevated like this installer
  Exec '"$WINDIR\explorer.exe" "$INSTDIR\${EXE}"'
FunctionEnd

!macro StopAll
  ; net stop waits until the service has stopped and released its files
  nsExec::Exec 'taskkill.exe /F /IM ${EXE}'
  nsExec::Exec 'net.exe stop ${SVC}'
!macroend

Section "MAE Routing" SecMain
  SetRegView 64
  SetShellVarContext all
  !insertmacro StopAll

  SetOutPath "$INSTDIR"
  File "${SRCDIR}\maeroutingd.exe"
  File "${SRCDIR}\mae-routing.exe"
  File "${SRCDIR}\${EXE}"
  File "${SRCDIR}\wintun.dll"
  File "${SRCDIR}\THIRD-PARTY-NOTICES.txt"
  File "${SRCDIR}\LICENSE-wintun.txt"
  File "${ASSETS}\MAERouting.ico"

  ; service: create once, then just start the new binary on upgrades
  nsExec::ExecToStack 'sc.exe query ${SVC}'
  Pop $0
  Pop $1
  ${If} $0 != 0
    DetailPrint "กำลังติดตั้งบริการ MAE Routing…"
    nsExec::ExecToLog '"$INSTDIR\maeroutingd.exe" install-system-daemon'
    Pop $0
    ${If} $0 != 0
      MessageBox MB_ICONSTOP "ติดตั้งบริการ MAE Routing ไม่สำเร็จ (รหัส $0)"
      Abort
    ${EndIf}
  ${EndIf}
  nsExec::ExecToLog 'net.exe start ${SVC}'

  WriteRegStr HKLM "${RUNKEY}" "${APP}" '"$INSTDIR\${EXE}"'
  ; "mae-routing" in Command Prompt / PowerShell
  InitPluginsDir
  File "/oname=$PLUGINSDIR\path.ps1" "${SRCDIR}\..\..\windows\path.ps1"
  nsExec::Exec 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\path.ps1" -Dir "$INSTDIR"'
  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\MAERouting.ico"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "${UNINST}" "DisplayName" "${APP}"
  WriteRegStr HKLM "${UNINST}" "DisplayVersion" "${VERSION}-${BUILD}"
  WriteRegStr HKLM "${UNINST}" "Publisher" "MAE Routing (maesuaisystem.com)"
  WriteRegStr HKLM "${UNINST}" "URLInfoAbout" "https://routing.maesuaisystem.com/"
  WriteRegStr HKLM "${UNINST}" "DisplayIcon" "$INSTDIR\MAERouting.ico"
  WriteRegStr HKLM "${UNINST}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINST}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINST}" "EstimatedSize" 60000

  ; silent installs (/S) have no finish page: start the tray here
  ${If} ${Silent}
    Call LaunchTray
  ${EndIf}
SectionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext all
  nsExec::Exec 'taskkill.exe /F /IM ${EXE}'
  nsExec::Exec 'net.exe stop ${SVC}'
  InitPluginsDir
  File "/oname=$PLUGINSDIR\path.ps1" "${SRCDIR}\..\..\windows\path.ps1"
  nsExec::Exec 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\path.ps1" -Dir "$INSTDIR" -Remove'
  nsExec::ExecToLog '"$INSTDIR\maeroutingd.exe" uninstall-system-daemon'
  Sleep 1000
  Delete "$INSTDIR\maeroutingd.exe"
  Delete "$INSTDIR\mae-routing.exe"
  Delete "$INSTDIR\${EXE}"
  Delete "$INSTDIR\wintun.dll"
  Delete "$INSTDIR\THIRD-PARTY-NOTICES.txt"
  Delete "$INSTDIR\LICENSE-wintun.txt"
  Delete "$INSTDIR\MAERouting.ico"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APP}.lnk"
  DeleteRegValue HKLM "${RUNKEY}" "${APP}"
  DeleteRegKey HKLM "${UNINST}"
  ; %ProgramData%\MAERouting (this machine's keys and settings) is kept so a reinstall stays logged in
SectionEnd
