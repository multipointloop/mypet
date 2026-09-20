@echo off
call "E:\desktop pet\devnv.bat"
cd /d "E:\desktop pet\mypetndroid"
sdkmanager --list 2>&1
echo SDK_EXIT=%ERRORLEVEL%
