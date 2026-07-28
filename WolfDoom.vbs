' WolfDoom - launch with no console window.
' Double-click this instead of play.bat; play.bat still works when you
' want to see build output in a terminal.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "cmd /c """ & root & "\play.bat""", 0, False
