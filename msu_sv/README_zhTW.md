# MSU SystemVerilog — 依目前 C model 轉換

這份 RTL 以你上傳的 `msu_model(1).c`、`msu_model(1).h`、`io_types(6).h` 為依據。
合法輸入下，buffer、輸出資料、位址與事件時序都與原 C model 逐拍比對。
固定規格為兩個完整結果 buffer、8×8 INT32 輸入、256-bit 寫出介面。
MSU 只儲存與寫出已完成的結果，沒有跨 K 累加或 read-modify-write。

| 檔案 | 用途 |
|---|---|
| `rtl/msu_pkg.sv` | 矩陣、metadata、status、events 的型別 |
| `rtl/msu.sv` | 可綜合 MSU 主模組 |
| `tb/tb_msu.sv` | 逐拍 C golden 比對；使用程序式 `$fatal`，沒有 SVA／DPI／UVM |
| `vectors/msu_vectors.txt` | 已產生的完整測試向量，跑 ModelSim 不需先編譯 C |
| `sim/run_msu.do` | ModelSim／Questa 編譯、模擬與波形腳本 |
| `reference/` | 原始 C 檔案，僅將檔名恢復為 include 所需名稱，內容未修改 |
| `tools/gen_msu_vectors.c` | 呼叫原 C model，產生測試向量 |
| `tools/run_verilator.sh` | 重跑原 C 測試、產生向量、lint、執行 Verilator |
| `tools/run_iverilog.sh` | 使用已附向量執行 Icarus |
| `results/` | 實際驗證紀錄 |

解壓縮後，在 ModelSim 的 Transcript 將工作目錄切到本資料夾，執行：

```tcl
do sim/run_msu.do
```

手動建立專案時，依序編譯 `rtl/msu_pkg.sv`、`rtl/msu.sv`、`tb/tb_msu.sv`，
simulation top 選 `tb_msu`。測試預設從目前工作目錄尋找
`vectors/msu_vectors.txt`，也可用 `+VECTORS=完整檔案路徑` 指定。
綜合 top 選 `msu`，只加入兩個 `rtl/` 檔案。
這個 standalone 測試不需要編譯 MLU、DU/TIA、Bridge 或 Tensor Core。

Linux 可用 `bash tools/run_verilator.sh` 或 `bash tools/run_iverilog.sh`。
若需 VCD，加上 `+VCD=results/msu.vcd`；ModelSim 腳本本身會加入主要波形。

| 介面 | 意義 |
|---|---|
| `clk`, `rst_n` | 正緣觸發；低有效非同步 reset，系統端應妥善同步 reset 解除 |
| `result_valid`, `result_ready` | 同拍都為 1，才接收一個完整結果 |
| `result[7:0][7:0][31:0]` | 64 個 INT32 bit pattern；`result[row][col]` |
| `result_meta.tile_id` | 32-bit tile 識別碼 |
| `result_meta.dst_addr` | 64-bit byte address，必須為 32-byte 對齊 |
| `write_valid`, `write_ready` | 同拍都為 1，記憶體 endpoint 才提交這一筆 32-byte 寫入 |
| `write_addr` | `dst_addr + row*32` |
| `write_data[255:0]` | 當前一整行，little-endian byte lanes |
| `write_last` | 當前行為第 7 行，可能因 stall 連續維持 1 |
| `write_meta` | 當前輸出 tile 的 metadata |
| `status` | 當前拍的組合式格式檢查結果，正常為 `IO_OK` |
| `events` | 最近一個正緣實際發生的事件，為 registered observation |
| `buffer_count`, `head_index`, `row_index` | 可觀察狀態：0～2、0～1、0～7 |

`events.result_accepted` 表示剛剛收進一個 TC 結果；
`events.beat_written` 表示剛剛提交一筆寫入；
`events.tile_done` 只有在第 7 行成功握手時才為 1。
`events.completed` 此時保存完成 tile 的 metadata，其餘拍為零。
這些事件在正緣後反映該正緣的動作，不要用它們取代同一正緣前的 ready/valid 判斷。

輸出排列與 C 的 `write_data[4*j+byte]` 相同：

```systemverilog
write_data[32*j +: 32]       = result[row][j];
write_data[8*(4*j+b) +: 8]   = result[row][j][8*b +: 8];
```

例如元素 `32'h01234567` 的四個 byte 依位址遞增是 `67 45 23 01`。
負數的二補數位元完整保留；MSU 不對數值做加法、符號延伸或截短。
一個結果是 `8×8×4 = 256 bytes`。C 的 `IO_TILE_BYTES=160` 是 MLU 輸入
image 容量，不適用於 MSU 的輸出結果。

| 正緣前狀態／輸入 | 該正緣的行為 |
|---|---|
| buffer 空，輸入有效 | 收進結果；沒有 empty bypass，最早下一個正緣才寫出 row 0 |
| 有資料，`write_ready=0` | 正常無錯誤時，保持 valid、位址、資料、last 與 metadata |
| count=1，寫出 row 0～6，同時收到新結果 | 寫出目前一行，收進另一個 buffer，count 變 2 |
| count=1，寫出 row 7，同時收到新結果 | 舊 tile 完成，新 tile 入槽，count 仍為 1 |
| count=2，當拍寫出 row 7 | 當拍 `result_ready=0`；完成後 count 變 1，下一拍才恢復 ready |

最後一列刻意保留 C 的 old-state 判斷；沒有加入「即將釋放槽位就提前 ready」的優化。
輸出由已儲存的 head buffer 選出當前行，沒有額外 output register 或 pipeline latency。
輸入端在 `result_valid && !result_ready` 時，應保持 valid、矩陣與 metadata，直到接受。
正常結果流不需要知道原本是 dense、hybrid 或 dual 模式。

格式檢查保留 C 的兩項條件：位址需 32-byte 對齊，且
`dst_addr <= 64'hffff_ffff_ffff_ff00`，避免整個 256-byte 結果超出位址範圍。
只有 `result_valid=1` 且尚有容量時才檢查；滿槽時是正常 backpressure，並非錯誤。

**錯誤與 reset 的明確差異：**C 的 `msu_peek()` 在 tick 之前回報容量與輸出，
但非法位址會讓 `msu_tick()` 回傳 `IO_BAD_FORMAT`，取消整拍、不更新狀態。
RTL 同樣取消狀態更新與事件，並在錯誤拍額外拉低 `result_ready`、`write_valid`，
避免外部 endpoint 誤認已提交寫入。因此非法輸入拍的兩條握手線不是 raw C peek 的值；
testbench 對這個差異有明確處理。Reset 期間也禁止握手。
非法位址屬介面 fault，不能當作一般 stall：producer 必須修正來源或由系統 reset 處理。
一般 valid/payload 的停頓保持承諾以合法交易為前提；此介面不是 AXI。

接到現有 Tensor Core 時，`msu_matrix_t` 與你 `tensor_core_pkg::tc_matrix_t`
都是 `logic [7:0][7:0][31:0]`，因此矩陣可直接連接，不需轉置或改 lane order。
`result_meta` 由 Bridge 的 result metadata queue head 提供，TC 本身沒有這組 metadata。
不同 package 的 metadata 建議以 `tile_id`、`dst_addr` 欄位分別對接。

以下是 top wrapper 中正常、無 TC error 時的連線關係；訊號名稱為示意：

```systemverilog
assign msu_result_valid    = tc_result_valid && meta_valid;
assign tc_result_ready    = msu_result_ready && meta_valid;
assign bridge_result_accept = msu_result_valid && msu_result_ready;
// msu.result      <- tc.result
// msu.result_meta <- bridge result metadata head
```

Bridge metadata 必須在 **TC→MSU 接收的同一個正緣** pop；不要等 `tile_done`，
也不要直接用延後一拍的 `events.result_accepted` 去驅動同拍 pop。
MSU 已在接收時把 metadata 複製到自己的結果 buffer。
若 top 允許目前 TC 的 strict-contract 錯誤發生，也要一起阻止該拍下游交易，
避免 TC 取消 tick 而 MSU 卻已收走結果。正常整合應遵守 TC 原有的輸入契約。
所有相連模組與 memory responder 應一起 reset，避免舊結果對到新 metadata。

這裡的 `write_ready` 表示該拍寫入已提交，沒有獨立 write response／error channel。
若要接 AXI/HBM controller，仍需轉接層，不能把本介面直接當成 AXI AW/W/B。
MLU/MSU 若共用不允許同時讀寫的記憶體埠，仲裁應在外部控制 request 與
`write_ready`；單獨 MSU 不會處理 MLU 的讀取請求。
Reset 會清掉 MSU 尚未完成的 buffer，但不會回復記憶體中 reset 前已提交的行。

已實際完成的驗證是 GCC 原 C 測試、Verilator 5.020 RTL lint／模擬、
Icarus Verilog 12.0 模擬。ModelSim 腳本已提供，但目前環境沒有 ModelSim，未實際執行；
也尚未進行 FPGA／ASIC 綜合、時序分析或整條 Tensor Core 系統的整合驗證。

| 檢查 | 結果 |
|---|---|
| 原始 `tb_msu.c` | PASS：120 results、960 beats、1,339 cycles、simultaneous=1 |
| C／SV 逐拍比對 | PASS：8,683 cycles，兩套 SV 模擬器結果一致 |
| 接收／寫入／完成 | 676 results、5,394 beats、673 completed tiles |
| 同拍接收與最後一行寫入 | 34 次，其中 directed test 明確安排 32 次 |
| 非法位址／reset | 42 次／8 次 |
| 輸出 stall | 3,216 拍，檢查所有輸出 payload 保持 |
| count=2 時寫出最後一行 | 632 次，檢查當拍仍不接受新結果 |
| head wrap／最高 count | 335 次／2 |

接收 676 個而只完成 673 個是 reset 測試刻意清掉 3 個未完成結果；
5,394 個寫入中有 10 個屬於 reset 前已提交、但整個 tile 尚未完成的行。
測試包含 INT32_MIN/MAX、負數與零、完整 64-bit 位址、最高合法位址、
滿槽、長停頓、最後一行停頓、非法輸入造成整拍取消，以及 reset 後重新開始。
