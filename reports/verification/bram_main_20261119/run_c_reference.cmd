@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
if errorlevel 1 exit /b 1
call "%~dp0..\..\..\tools\run_c_tests.bat"
exit /b %errorlevel%
