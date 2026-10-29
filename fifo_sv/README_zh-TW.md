# FIFO／Bridge 獨立單元驗證版

本程式包只驗證 `du_tc_bridge`。testbench 沒有例化 MLU、DU/TIA、Tensor Core 或 MSU。各 unit 單獨通過後，再進行完整系統整合驗證。

本次調整驗證程式包與執行入口，移除局部整合 wrapper、整合 testbench、整合執行腳本及其他 unit 的 RTL。`du_tc_bridge.sv`、`du_tc_bridge_pkg.sv`、`tb_bridge.sv` 保持原版本，硬體介面、時序、credit 與 metadata 行為未變更。

## 在 ModelSim／Questa 執行

解壓縮整個 ZIP，保留 `vectors/` 子目錄。在 Transcript 切到 `fifo_sv` 資料夾後執行：

```tcl
do run_bridge.do
```

也可以直接指定腳本完整路徑：

```tcl
do {C:/你的路徑/fifo_sv/run_bridge.do}
```

腳本依序編譯四個檔案，模擬 top 為 `tb_bridge`：

| 編譯順序 | 檔案 | 用途 |
|---|---|---|
| 1 | `tensor_core_pkg.sv` | 共用 packet 型別與常數；不是 TC 電路 |
| 2 | `du_tc_bridge_pkg.sv` | Bridge 狀態、metadata、FIFO entry 型別 |
| 3 | `du_tc_bridge.sv` | 唯一的待測硬體 unit |
| 4 | `tb_bridge.sv` | 驅動 Bridge 接腳並檢查結果 |

保留 `tensor_core_pkg.sv` 是因為 FIFO 使用其中的 `tc_input_packet_t`。**編譯 package 不會例化 Tensor Core**；此包不包含 `tensor_core.sv`，能獨立於 TC 電路執行。

成功時會顯示：

```text
BRIDGE RTL PASS: C-equivalent rows=19147 rejected_edges=7156 resets=13
```

預期資料已附在 `vectors/bridge_vectors.txt`；使用 ModelSim 時不用執行 C 或 Python。測試平台用一般 `if`／`$fatal` 檢查，沒有 SVA，也不需要 DPI。本環境以 Verilator 實跑；ModelSim／Questa 腳本尚未實跑。

## 沒有其他 unit，外部訊號如何產生

testbench 讀取原始 C model 產生的輸入與預期值，直接驅動 Bridge 邊界：

| Bridge 接腳 | 單元測試中的用途 |
|---|---|
| `issue / issued_mode / issued_k / issued_meta` | 模擬上游確實送入 DU/TIA 一筆資料的事件 |
| `du_valid / du_packet` | 模擬四級延遲後的 DU/TIA 輸出，不執行解碼電路 |
| `tc_accept` | 模擬下游接受 FIFO head，不執行矩陣運算 |
| `result_accept` | 模擬一個 tile 結果被接收，釋放 metadata |
| `rst_n` | 清除 Bridge 狀態，搭配驅動器取消未完成事件 |

每筆紀錄都比對 status、所有 sideband／FIFO／metadata 暫存器、計數器、head 與 result metadata。刻意違反契約時，會預期非 `IO_OK` 並確認整個 Bridge 狀態不變；這不代表正常滿槽應該報錯。

`c_reference/` 保留本次上傳的原始 C model、headers 與 standalone testbench，僅恢復 include 使用的檔名，內容未修改。額外的 `generate_vectors.c` 呼叫原始測試，加入四組固定 seed 的隨機時序，再輸出預期值。C struct 與 SV packed struct 的布局不同，輸出工具逐欄位轉換，不直接複製 C 記憶體。

## 單元驗證涵蓋範圍

- 連續輸入、輸入空拍及下游停頓。
- FIFO 到 8 筆、inflight 到 4 筆、result metadata 到 2 筆。
- packet 內容、資料順序、k、tile ID、64-bit destination address。
- 同拍 FIFO push/pop、同拍 metadata push/pop、指標循環。
- 沒 credit、metadata 滿槽阻擋新 tile、DU 時序／模式錯誤。
- 在途資料、FIFO 有資料或 metadata 有資料時 reset，重新開始後不殘留舊資料。
- 共 19,147 筆輸入／狀態紀錄，含 7,156 次預期拒收、13 次 reset。

這是 FIFO／Bridge 的功能與週期行為驗證。DU 解碼、TC 矩陣運算與真正 MLU/MSU 的端到端交握，留給各自單元測試及之後的完整整合。

## 保留的硬體行為

Packet FIFO 是 8 entries、DU/TIA metadata sideband 是 4 stages、result metadata queue 是 2 entries。

`fifo_count + inflight_count <= 8`。`issue` 預留 credit，DU arrival 將 credit 從 inflight 移到 FIFO，`tc_accept` 才釋放。`can_issue` 只看目前暫存器，沒有同拍 credit 重用。

DU 輸出先寫入 FIFO，下一拍 TC 才能取走；沒有 payload bypass。FIFO head 由組合邏輯選出，沒有額外 output register。

當 head 的 `k=0` 且 result metadata 已滿，`head_valid=0`。metadata 在 tile 第一筆被 TC 接受時入隊，在 **TC→MSU 實際交握**時出隊，不等待 HBM 寫回完成。

`side[]` 是真正的四級 tag 暫存器，只保存 `valid / is_sparse / meta / k`。完整運算 payload 由外部 DU/TIA 處理，輸出後才寫入 FIFO。

| 接腳 | 整合時的意義 |
|---|---|
| `can_issue` | 上游可否再送一筆到 DU/TIA |
| `issue` | 本邊緣實際送入 DU/TIA；不是單純想送 |
| `du_valid / du_packet` | DU/TIA 舊 S3 輸出，沒有 ready 接腳 |
| `head_valid / head_entry` | 目前有資格送往 TC 的資料 |
| `tc_accept` | 本邊緣實際 FIFO→TC transfer |
| `result_meta_valid / result_meta` | 目前最舊的未消耗結果 metadata |
| `result_accept` | 本邊緣實際 TC→MSU transfer |
| `status` | 當前輸入在下一個邊緣可否提交，屬於組合輸出 |

`head_entry` 在 FIFO 非空時呈現 head，即使 metadata 阻擋而 `head_valid=0` 仍可能有值；只有 head valid 且 TC 可接受時才可消耗。FIFO 空時輸出零。

資料欄位：`tile_id` 32-bit、`dst_addr` 64-bit、`k` 8-bit unsigned，合法 k 為 0..7；mode 為 2-bit，0=dense、1=hybrid、2=dual、3=非法。payload 沿用現有 packet 型別，INT8 bit pattern 直接保存。

**正常滿槽是停頓，不是錯誤。** `can_issue=0` 時讓上游等待；此時仍宣告 `issue=1` 才會得到 `IO_NO_CREDIT`。其他狀態包括 `IO_BAD_FORMAT`、`IO_PROTOCOL_ERROR`；`IO_BAD_ARGUMENT` 只對應 C 的 NULL pointer，RTL 不會產生。

與 C 一致，非 `IO_OK` 時 Bridge 不提交該 edge。這是診斷契約違反的行為，不能用來暫停外部 DU/TIA；整合發生此類錯誤時，應修正來源並同步 reset 相關模組。

上游須保證每 tile 八筆、k 依序 0..7、tile 內 metadata 一致。Bridge 保留 C 的檢查範圍，不額外檢查上述序列規則。

## 完成單元驗證後

所有 unit 各自通過後，直接接完整系統。先測三種模式的單 tile，再加入連續多 tile、輸入空拍與輸出停頓；不需要先執行 DU/TIA＋FIFO＋TC 的局部整合測試。

完整整合時須同步 reset DU/TIA、Bridge、TC，並讓 sideband 對齊實際 DU/TIA 四級延遲。你目前 TC 的 valid 採 strict contract，送入前須確認 mode-aware `in_ready`，不是只看當前模式的 `input_ready`。即使 valid=0，head packet 仍須接到 TC，讓它判斷下一筆模式。

## Linux 重跑

```bash
python3 run_tests.py
python3 run_tests.py --regenerate
python3 run_tests.py --trace
```

三個命令都只跑 FIFO／Bridge。第一個使用已附預期值；第二個需要 gcc，會先重新執行原始 C model 與測試；第三個輸出 `bridge.vcd`。模擬需要 Verilator 與 C++ compiler。

腳本採 `-O0`，避免本環境 Verilator build 將 testbench 迴圈結束後的統計計數器錯誤常數化；這只改模擬器產生 C++ 的最佳化，沒有改 RTL。腳本也保留已驗證的 Linux/GCC precompiled header 設定。

尚未執行 FPGA／ASIC synthesis 或 P&R，沒有新的 Fmax、面積或功耗結果。
