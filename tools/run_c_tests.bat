@echo off
setlocal
rem Run from a Visual Studio Developer Command Prompt with C11 support.
rem Compile existing models/tests without changing vectors or random seeds.
where cl >nul 2>nul
if errorlevel 1 (
  echo Run from a Visual Studio Developer Command Prompt with cl on PATH.
  exit /b 1
)
set "STC_TEST_ROOT=%~dp0.."
if not exist "%STC_TEST_ROOT%\build\c_reference" mkdir "%STC_TEST_ROOT%\build\c_reference"
pushd "%STC_TEST_ROOT%\build\c_reference"
set "STC_CFLAGS=/nologo /W4 /O2 /std:c11 /TC /utf-8 /D_CRT_SECURE_NO_WARNINGS"
cl %STC_CFLAGS% "%STC_TEST_ROOT%\tensor_core_sv\c_reference\tensor_core_model.c" "%STC_TEST_ROOT%\tensor_core_sv\c_reference\tb_tensor_core.c" /Fe:tc_test.exe
if errorlevel 1 goto fail
tc_test.exe
if errorlevel 1 goto fail
cl %STC_CFLAGS% "%STC_TEST_ROOT%\mlu_sv\c_ref\mlu_model.c" "%STC_TEST_ROOT%\mlu_sv\c_ref\tb_mlu.c" /Fe:mlu_test.exe
if errorlevel 1 goto fail
mlu_test.exe
if errorlevel 1 goto fail
cl %STC_CFLAGS% "%STC_TEST_ROOT%\msu_sv\reference\msu_model.c" "%STC_TEST_ROOT%\msu_sv\reference\tb_msu.c" /Fe:msu_test.exe
if errorlevel 1 goto fail
msu_test.exe
if errorlevel 1 goto fail
cl %STC_CFLAGS% "%STC_TEST_ROOT%\fifo_sv\c_reference\du_tc_bridge.c" "%STC_TEST_ROOT%\fifo_sv\c_reference\tb_bridge.c" /Fe:bridge_test.exe
if errorlevel 1 goto fail
bridge_test.exe
if errorlevel 1 goto fail
cl %STC_CFLAGS% "%STC_TEST_ROOT%\c code\DU & TIA\DU & TIA\DU & TIA.c" /Fe:du_tia_test.exe
if errorlevel 1 goto fail
du_tia_test.exe
if errorlevel 1 goto fail
cl %STC_CFLAGS% "%STC_TEST_ROOT%\c code\Tensor Core Outer Product\Tensor Core Outer Product\outer product.c" /Fe:outer_product_test.exe
if errorlevel 1 goto fail
outer_product_test.exe
if errorlevel 1 goto fail
echo C REFERENCE SUITE PASS
popd
exit /b 0
:fail
echo C REFERENCE SUITE FAILED
popd
exit /b 1
