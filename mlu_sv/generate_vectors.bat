@echo off
setlocal
cd /d "%~dp0"
if not exist build mkdir build
if not exist logs mkdir logs
where cl >nul 2>nul
if errorlevel 1 (
  echo Run this file from a Visual Studio Developer Command Prompt.
  exit /b 1
)
cl /nologo /std:c11 /W4 /O2 /TC /I c_ref c_ref\mlu_model.c c_ref\tb_mlu.c /Fe:build\tb_mlu_c.exe /Fo:build\
if errorlevel 1 exit /b 1
cl /nologo /std:c11 /W4 /O2 /TC /I c_ref c_ref\mlu_model.c c_ref\gen_mlu_vectors.c /Fe:build\gen_mlu_vectors.exe /Fo:build\
if errorlevel 1 exit /b 1
build\tb_mlu_c.exe > logs\c_baseline.log
if errorlevel 1 exit /b 1
build\gen_mlu_vectors.exe mlu_vectors.txt %1 > logs\c_vectors.log
if errorlevel 1 exit /b 1
type logs\c_baseline.log
type logs\c_vectors.log
endlocal
