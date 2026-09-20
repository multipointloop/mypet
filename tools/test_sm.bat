@echo off
rem MyPet Android SDK 冒烟测试
rem 把 <PROJECT_ROOT> 换成本机项目根目录后运行
call "<PROJECT_ROOT>\dev\env.bat"
cd /d "<PROJECT_ROOT>\mypet\android"
sdkmanager --list 2>&1
echo SDK_EXIT=%ERRORLEVEL%
