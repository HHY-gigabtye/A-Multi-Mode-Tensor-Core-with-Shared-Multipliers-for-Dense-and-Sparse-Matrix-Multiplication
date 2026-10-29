@echo off
setlocal
pushd "%~dp0"
where cl >nul 2>nul
if errorlevel 1 (
  echo Run this script from the Visual Studio x64 Native Tools Command Prompt.
  popd
  exit /b 1
)
cl /nologo /W4 /O2 /std:c11 /TC c_reference\tensor_core_model.c c_reference\generate_c_vectors.c /Fe:generate_c_vectors.exe
if errorlevel 1 (
  popd
  exit /b 1
)
generate_c_vectors.exe c_vectors.txt %* > c_reference_results.txt
set tc_exit_code=%errorlevel%
type c_reference_results.txt
popd
exit /b %tc_exit_code%
