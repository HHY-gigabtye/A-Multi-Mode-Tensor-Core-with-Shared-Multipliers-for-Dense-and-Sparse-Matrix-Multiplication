# MLU、MSU、Bridge 三個獨立 C 專案

這份封包配合「各模組 C → 各模組 SV → 完整 SV 整合」的流程。
三個 model 與原封包完全相同；新增 bridge 的獨立 testbench，並預先建立三個 Visual Studio Console 專案。
每個專案各自產生一個執行檔，不需要連結 DU/TIA 或 Tensor Core 的 `.c`。

## 開啟方式

1. 完整解壓縮，保留 `reference` 和 `vs` 資料夾的位置。
2. 開啟根目錄的 `MLU_MSU_BRIDGE.sln`。
3. 選擇 `Debug`、`x64`，建置方案。
4. 在方案總管對要執行的專案按右鍵，選「設定為啟始專案」，再按 `Ctrl+F5`。
5. 依序執行 `MLU_Test`、`MSU_Test`、`Bridge_Test`。建置整個方案不代表已執行三份測試。

專案已設定 C11、Compile as C、停用預先編譯標頭；不要新增含有另一個 `main()` 的預設 `.cpp`。
此方案使用 VS 2022 的 v143 工具集；在 VS 2019 中會選 v142，VS 2019 需 16.8 或更新版本。
電腦需安裝 C++ 桌面開發工具與支援 C11 的 Windows SDK（10.0.20348.0 或更新）。
若提示工具集或 SDK 未安裝，請在專案屬性選擇已安裝且支援 C11 的版本，或補裝對應工具集。
相關官方說明：https://learn.microsoft.com/zh-tw/cpp/overview/install-c17-support?view=msvc-170

## 三個專案應該放什麼

| 專案 | Source Files：只有這兩個 `.c` 參與編譯 | Header Files |
|---|---|---|
| MLU_Test | `tb_mlu.c`、`mlu_model.c` | `mlu_model.h`、`io_types.h`、`tb_support.h`、`reference/tensor_core_model.h` |
| MSU_Test | `tb_msu.c`、`msu_model.c` | `msu_model.h`、`io_types.h`、`tb_support.h`、`mlu_model.h`、`reference/tensor_core_model.h` |
| Bridge_Test | `tb_bridge.c`、`du_tc_bridge.c` | `du_tc_bridge.h`、`io_types.h`、`reference/tensor_core_model.h` |

MSU_Test 需要 `mlu_model.h`，是因為原有 `tb_support.h` 共用測試工具會 include 它；不需要連結 `mlu_model.c`。
`io_types.h` 引用 `reference/tensor_core_model.h` 的封包與矩陣型別，所以三個專案都需要這個 header。
只有宣告而沒有呼叫的 TC 函式不需要其 `.c` 實作。
Header Files 是 IDE 的檔案分組，不是另外編譯的程式；已提供的專案都指向封包根目錄同一份檔案，不用複製三份。

## 原封包保留哪些檔案

| 處理方式 | 檔案 |
|---|---|
| 保留 | `mlu_model.c/.h`、`msu_model.c/.h`、`du_tc_bridge.c/.h`、`io_types.h` |
| 保留 | `tb_mlu.c`、`tb_msu.c`、`tb_support.h` |
| 保留資料夾與其中這個 header | `reference/tensor_core_model.h` |
| 新增 | `tb_bridge.c`、`MLU_MSU_BRIDGE.sln`、`vs/` 下三個專案與 filters |
| 本次獨立測試不用，可留在原封包備份 | `tb_pipeline.c`、`du_reference.inc`、`reference/du_tia_reference.c`、`reference/tensor_core_model.c` |
| 換成此封包的版本 | `Makefile`、`build_msvc.bat`、`README_zh_TW.md`、`verification.txt` |

舊的 Makefile 和 build_msvc.bat 仍會編譯 C 整合測試；如果拿掉整合相關檔案，就必須改用這一版腳本。
你原本另外完成的 DU/TIA 與 TC 專案、SV 檔案仍保留，後續整合會用到。

## Bridge_Test 測試範圍

這份 testbench 只連結 `du_tc_bridge.c`，用假的周邊輸入模擬：

- MLU 接受 issue 後，DU 在四拍後回傳對應 payload；排程由 testbench 自己保存，不讀 bridge 的 side 管線來產生回傳。
- TC 暫時停收、恢復收取；結果只在該 tile 的八個封包都被 TC 端接受後，才允許消耗 metadata。
- 以單調遞增的 token 編號獨立核對 payload、k、tile ID、64-bit 寫回地址、順序與計數。

涵蓋：空讀保護、錯誤 k/mode、DU 回傳時機與模式錯誤、錯誤呼叫保持狀態、
長時間停止接收、FIFO 滿八筆、最多四筆在途資料、同拍入隊/出隊、指標繞回、
兩筆結果 metadata 滿載與阻擋、metadata 同拍進出，以及三種有資料狀態下 reset 後重新送入不同 tile ID。

bridge 的封包容量定義為 `used = FIFO.count + inflight <= 8`。
送入 DU 前就預留容量；DU 輸出進 FIFO 只搬移占用位置；TC 真正接受才釋放。
本版只使用舊狀態決定是否可送入，滿載這拍即使 TC 取走資料，新 credit 仍從下一拍開始使用。
沒有 FIFO payload bypass：新到達的 DU 輸出要下一拍才能交給 TC。

這是 bridge 的單元測試，不驗證 DU 解碼、TC 運算或整體模式切換協定。
未連結實際 DU/TC，因此不能取代將來的完整 SV 整合測試。

## MLU 與 MSU 行為摘要

- 每項任務是一個獨立的 8×8×8 INT8 矩陣乘法，結果 INT32；MSU 不做跨 K 區塊累加。
- MLU 有兩個 tile buffer，先載入完整 tile，再依 k=0..7 輸出 DU 封包。
- MLU 每次只允許一筆未完成的讀取 burst；32 bytes/beat，讀取與輸出都可以停頓。
- dense image 為 128 bytes，hybrid 為 120 bytes（讀 128 bytes），dual 為 144 bytes（讀 160 bytes）。
- MLU 不負責壓縮；輸入記憶體中的資料已打包。C struct 不等於 SV packed union 的位元排列。
- MSU 有兩個完整結果 buffer；每個結果為 256 bytes，以 row-major 分八個 32-byte beat 寫回。
- MSU 的 `write_ready` 在此簡化介面代表該拍寫入已提交；未建模 AXI write response 或真實 HBM 控制器。
- 實際系統 reset 時，所有相連模組和未完成記憶體交易需協調處理；已寫入記憶體的資料不會自動回復。

完整資料排列與介面註解保留在原始封包 README 及各 model 的 header。此封包專注三個模組的獨立操作。

## 其他編譯方式

GCC：在此目錄執行 `make test`。

Visual Studio Developer Command Prompt：在此目錄執行 `build_msvc.bat`，會依序建置並執行三份測試。
`.bat` 與 `.sln` 是兩種使用方式，選一種即可。

手動建置對應來源檔：

```text
MLU_Test    = tb_mlu.c    + mlu_model.c
MSU_Test    = tb_msu.c    + msu_model.c
Bridge_Test = tb_bridge.c + du_tc_bridge.c
```

每個執行檔只包含一個 `main()`。不要把三個 testbench 全部加入同一個專案編譯。

## 驗證狀態

實際執行結果記錄在 `verification.txt`。
目前執行環境是 GCC；Visual Studio 專案已檢查 XML、來源引用及唯一 main，但尚未在 Windows/MSVC 執行。
本次沒有產生 MLU/MSU/bridge 的 SV，也未執行 ModelSim 或 ASIC 合成。
