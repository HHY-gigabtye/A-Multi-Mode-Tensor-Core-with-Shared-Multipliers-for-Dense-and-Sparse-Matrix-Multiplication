# Tensor Core SystemVerilog — sparse overlap 版本

本版以這次提供的 `tensor_core_model(1).c/.h` 和 `tb_tensor_core(1).c` 為依據。
`c_reference/` 內的三份原始 C 檔只有移除檔名的 `(1)`，內容未修改。
僅包含 Tensor Core；輸入是已完成 DU/TIA 解碼的封包。

## 在 ModelSim 執行

1. 解壓整個資料夾，保留 `c_vectors.txt` 和 `.sv` 檔的相對位置。
2. 在 ModelSim 的 Transcript 輸入（換成你的實際路徑）：

   ```tcl
   do C:/your/path/tensor_core_sv/run_modelsim.do
   ```

腳本會編譯、載入波形並執行完整測試。已附產生好的 C 參考向量，**不必先裝 GCC 或編譯 C**。
如果手動建立 ModelSim project，編譯順序如下，simulation top 選 `tb_tensor_core`：

```tcl
vlog -sv tensor_core_pkg.sv tensor_core.sv tb_tensor_core.sv
vsim -onfinish stop -voptargs=+acc work.tb_tensor_core +VECTORS=c_vectors.txt
run -all
```

手動執行時，工作目錄必須是這個資料夾，或把 `+VECTORS=` 改為向量檔路徑。
RTL 和 SV testbench 均未使用 `assert` / SVA、UVM、class 或 DPI。
失敗時使用一般 `if`、`$display` 和 `$fatal` 回報。

## 檔案

| 檔案 | 用途 |
|---|---|
| `tensor_core_pkg.sv` | 封包、PE、pipeline、控制暫存器與型別 |
| `tensor_core.sv` | 核心 RTL，只有此檔和 package 需要交給綜合工具 |
| `tb_tensor_core.sv` | 逐拍讀取 C 參考資料，比對介面、結果及內部狀態 |
| `run_modelsim.do` / `waves.do` | ModelSim 編譯、模擬與波形設定 |
| `c_vectors.txt` | 完整預先產生的測試向量，約 144 MiB |
| `c_reference/` | 原始 C model/testbench，加上向量產生器 |
| `generate_vectors.bat` / `.sh` | 需要更換 seed 或測試數量時重新產生向量 |
| `c_reference_results.txt` | 原始 C 測試結果 |
| `verification_results.txt` | 本次 Verilator C/SV 比對實測結果 |
| `SOURCE_SHA256.txt` | 三份原始 C 來源的 SHA-256 |

## 保留的行為

- 固定 M=N=K=8，signed INT8 × INT8，INT32 累加，初值為零。
- Dense：8×8 output-stationary systolic array，lane i 延遲 i 拍，每拍只跨一個 PE。
- Sparse：MUL → ROUTE → ACC，三者讀取前一拍暫存器；每個 tile 收 8 筆封包。
- Sparse 的下一個 tile 可以在第 9 筆輸入直接開始，不必等待前一個結果輸出。
- 每個 tile 第一筆輸入預留一個 result credit；最多同時 outstanding=2。
- 兩個實體 result slots，支援同拍 consume/publish 與 consume/start。
- FIFO 滿載時，只阻擋新 sparse tile 的第一筆；已開始的 tile 仍可接收剩餘資料。
- `is_sparse` 只能在舊工作及結果全部 drain、busy=0 後切換。
- Sparse 在 `route.first` 到达 ACC 時才清 accumulator；不會在下一個 tile 輸入時提早清除。
- 空 outer product 仍傳遞 valid/first/last；有效 prefix 裡存放 0 是合法的。
- 消費結果後，無效的 result slot 保留舊值，與 C 相同。判斷結果請看 `result_valid`。

Dense 與 sparse 在 RTL 中經 operand mux 共用 64 個乘法運算位置。
Dense 的 PE accumulator、sparse accumulator 和兩個 result slots 分別保存；
C 的 state union 沒有直接轉成硬體共用儲存體。實際乘法器、DSP、面積與 Fmax 仍須由目標工具綜合確認。

## 時序

以接受第一筆輸入的 rising edge 為 cycle 0，連續接受 k=0..7：

| 事件 | Dense | Sparse |
|---|---:|---:|
| 最後一筆输入 | 7 | 7 |
| 最後一次累加 | 21 | 9 |
| result_valid 變 1 | 22 | 10 |
| result_ready 持續為 1 時，最早 consume | 23 | 11 |
| 下一個 tile 最早開始 | 24 | 8 |

有 gap 時，以最後一筆實際接受的 cycle 為基準：dense 在 +15 拍 publish，sparse 在 +3 拍 publish。
Publish 當拍不能消費「剛產生」的結果，只能消費該拍以前已有效的 FIFO head。
`result_ready` 不參與組合 readiness：本拍釋放的 credit 到下一拍才可用。

## 介面

| 訊號 | 意義 |
|---|---|
| `clk` / `rst_n` | 上升緣更新；低有效非同步 reset，清掉全部狀態及 debug info |
| `in_packet` | `tc_input_packet_t`；下一筆要送的封包 |
| `input_ready` | 對應 `tc_input_ready()`，只看目前模式的資源 |
| `in_ready` | 對應 `tc_input_ready_for(..., in_packet.is_sparse)`，加上模式檢查 |
| `in_valid` | 本拍提出有效封包；合法 driver 應只在 in_ready=1 時拉高 |
| `result_valid` / `result_ready` | FIFO head 有效 / 外部準備消費；在 rising edge 取走舊 head |
| `result` | `result[i][j]` 是 32-bit 二補數結果；顯示為十進位時用 `$signed(...)` |
| `busy` | 有尚未被消費的 tile，包括只輸入部分封包、pipeline 中、已完成的結果 |
| `status` | 目前輸入對下一個 rising edge 的組合檢查結果，非註冊脈衝 |
| `tick_info` | 最近一次 rising edge 的操作觀察值，對應 `TcTickInfo` |

`status` 的數值與 C enum 相同：OK=0、BAD_SPARSE_VECTOR=2、MODE_CHANGE=3、NOT_READY=4。
C 的 BAD_ARGUMENT=1 只適用 NULL pointer，硬體不會產生。
`tick_info` 用於驗證與看波形；整合成較大 top 時可不接，讓綜合工具移除未使用的 debug 邏輯。

**本版忠實保留 C 的 strict API，並非直接採用可持續拉高 valid 的一般串流協定。**
`in_valid=1` 且資源不 ready、模式不符或 sparse metadata 不合法時，**整個核心該拍保持狀態**，
連舊結果都不會 consume，`tick_info` 為零。要等待時請送 `in_valid=0`，讓 pipeline/output 繼續前進。
`in_ready` 不檢查 sparse count/index 合法性；上游須提供合法 metadata。

若上游已有 FIFO，且 FIFO head 可以保持，正常送法是：

```systemverilog
assign tc_in_packet = tensor_core_pkg::tc_input_packet_t'(fifo_head);
assign tc_in_valid  = fifo_valid && tc_in_ready;
assign fifo_pop     = fifo_valid && tc_in_ready;
```

上述假設 FIFO 提供合法封包。不能把一拍後就消失的 DU/TIA `out_valid` 單純與 ready 相 AND；
那會丟掉被阻擋的封包。現有 DU/TIA 沒有 ready port，接成整體系統時須由外部緩衝及上游發送控制
容納已在 DU/TIA pipeline 內的封包。本交付沒有修改 DU/TIA 或增加 MLU/MSU。

## 封包與 DU/TIA

本 package 的 `tc_input_packet_t` 是 185 bits，與提供的 `du_tia_pkg::du_tia_output_t`
欄位順序、寬度一致，可使用上面的型別轉換；Tensor Core 單獨編譯不依賴 du_tia_pkg。

- Dense：`payload.dense.dense_a[i] = A[i][k]`，`dense_b[j] = B[k][j]`。
- Sparse：`a/b.count` 是 0..8；有效位置是 value/index 的 0..count-1。
- Index 為 3 bits，原座標 0..7，prefix 內必須嚴格遞增。Padding 的值和 index 被忽略。
- Packed array 的 lane 0 是該 array 的最低位元組／欄位；請透過欄位索引填值。
- 不需要額外 k、tile_start、first、last 或原始 compiler mode 輸入。
- Hybrid、dual sparse、dense×unstructured 都以 is_sparse=1 走相同路徑。

## 本次驗證

1. 原始 C 測試通過：6,389 tiles，1,593,020 次 MAC。
2. 使用同一份原始 C testbench 攔截 public reset/tick 呼叫，產生 136,136 筆逐拍資料。
3. Verilator 實跑全部通過：169 筆 reset、13 筆可表示的 RTL 輸入拒絕情境；
   FIFO 滿載 3,480 拍，同拍 pop/push 1 次、consume/start 151 次。
4. 每筆核對 pre-edge readiness/status、post-edge 全部 TickInfo、busy/result_valid、
   **兩個 result slots 的所有 64 個 INT32 元素**，以及依欄位計算的內部狀態 32-bit hash。
   Hash 涵蓋控制暫存器及當前模式的所有 pipeline/accumulator 狀態，不使用 C struct padding。
5. 原始 C 另以獨立 i/j/k GEMM 核對數學結果、dense 波前時序、sparse pipeline、FIFO 次序與延遲。

測試涵蓋零值、極值、stored zero、gap、長時間 output hold、跨 tile overlap、模式切換、reset/restart。
NULL pointer 和 active index≥8 共 4 筆 C-only 拒絕呼叫由原始 C 測試檢查；SV 的 3-bit index
無法表示 ≥8。Padding index=255 在向量轉換時截為 7，但仍是不使用的 padding。
紀錄包含測試中途 reset 丟棄的工作，以及未納入 tiles 統計的 contract tests，
因此 publish/consume 計數不會與最後的 6,389 tiles 完全相同。

RTL 的 Verilator `--Wall` lint 已通過。SV 語法和腳本以 ModelSim 為目標，
但此環境未安裝 ModelSim，**這次實際模擬工具是 Verilator，不是 ModelSim**。
尚未執行 FPGA/ASIC 綜合、STA 或形式等價驗證；狀態 hash 比對也不等於形式證明。

## 重新產生測試資料（可選）

Windows：在支援 C11 的 Visual Studio「x64 Native Tools Command Prompt」執行：

```bat
generate_vectors.bat
generate_vectors.bat --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

Linux/GCC：

```bash
bash generate_vectors.sh
bash generate_vectors.sh --tests 100 --stream-tiles 100 --bench-tiles 20 --seed 12345
```

這會覆寫本地 `c_vectors.txt` 和 C 測試 log，再重新執行 `run_modelsim.do` 即可。
`generate_c_vectors.c` 引入原始 testbench 並重新命名其 main；編譯產生器時
**不要再把 tb_tensor_core.c 當成另一個 compilation unit 加入**。
內附 `run_verilator.sh` 可在已有 Verilator 的 Linux 環境執行同樣的 SV testbench。
