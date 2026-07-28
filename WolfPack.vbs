' WolfPack - launch with no console window.
' Double-click this instead of play.bat; play.bat still works when you
' want to see build output in a terminal. When Spear of Destiny has
' also been built (you own its data), ask which campaign to play.
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
game = ""
If fso.FileExists(root & "\dist\spear.ipk3") Then
    r = MsgBox("Play Spear of Destiny?" & vbCrLf & vbCrLf & _
               "Yes  -  Spear of Destiny" & vbCrLf & _
               "No   -  Wolfenstein 3D", vbYesNoCancel + vbQuestion, _
               "WolfPack")
    If r = vbCancel Then WScript.Quit
    If r = vbYes Then game = " spear"
End If
sh.Run "cmd /c """ & root & "\play.bat""" & game, 0, False
