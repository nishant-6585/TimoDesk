' Launches spine_service.cmd with no visible console window. A copy/shortcut of
' this file lives in the user's Startup folder so the spine starts at logon and
' keeps itself running (see spine_service.cmd).
CreateObject("Wscript.Shell").Run """" & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\spine_service.cmd""", 0, False
