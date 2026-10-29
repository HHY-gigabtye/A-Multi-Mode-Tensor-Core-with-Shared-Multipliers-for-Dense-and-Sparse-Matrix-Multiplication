# Sparse Tensor Core — Architecture and Project Handoff

> 更新／整理：2026-10-24。這是從先前設計討論及已提供的 MLU/MSU、Bridge、TC 參考文件整理的**交接文件**，不是對目前電腦資料夾所做的完整原始碼審查。帶有 **[VERIFY]** 的敘述需讓 Codex 對照本機最新實作與測試結果。

## 1. 目標與目前範圍

本專案實作支援 Dense 與 Sparse 的 8×8 Tensor Core，以 cycle-level C models 定義行為，再產生 SystemVerilog RTL、執行 regression，後續進行 ASIC synthesis 與 PPA 最佳化。

```text
Simplified memory/HBM model
       |
       v
  MLU (2 tile buffers; load + encode/packetize)
       | k=0..7, valid/ready
       v
  DU/TIA (S0-S3, 4-stage fixed pipeline; no out_ready)
       | decoded payload + aligned sideband
       v
  DU-TC Bridge: packet FIFO (8) + inflight credits
                + result metadata FIFO (2)
       | mode-aware gating
       v
  Tensor Core: dense systolic / sparse outer-product
               (2 result slots)
       | 8x8 INT32 matrix + ordered metadata
       v
  MSU (2 whole-result buffers; 8 write beats)
       |
       v
Simplified memory write endpoint
```

現在每個命令對應一個**獨立的 8×8×8 tile**；8 筆 k=0..7 封包，1 份 8×8 INT32 結果，**不做跨 K 區塊累加**。真實 HBM/AXI 的交易回應、共享讀寫仲裁、完整記憶體一致性不在目前簡化模型範圍。

## 2. 精度與模式

| 項目 | 設計契約 |
|---|---|
| 矩陣尺寸 | M=N=K=8；每 tile 八個 k slice |
| 乘數與被乘數 | signed INT8（-128 至 127） |
| 乘積 | 16-bit signed 足以容納單次 INT8×INT8 乘積 |
| Accumulator / result | signed INT32，結果 8×8 |
| `IO_DENSE=0` | dense A × dense B；8×8 systolic |
| `IO_HYBRID=1` | unstructured A × 2:4 structured B；sparse outer product |
| `IO_DUAL=2` | unstructured A × unstructured B；sparse outer product |
| `mode=3` | 非法 |

TC 接收的是**DU/TIA 已解碼的封包**：
- dense payload：`dense_a[8] = A[:,k]`、`dense_b[8] = B[k,:]`，由 TC 路徑自行處理必要的 input skew。
- sparse payload：A、B 各有 `count`（0..8）、`value[8]`、`index[8]`；只解讀前 `count` 筆，index 表示 0..7 原始 row/column 且遞增。有效的 stored zero 合法。
- 兩種 sparse mode 在解碼後對 TC 均用 `is_sparse=1`，不要把原始 2:4 bitmap 直接丟入 TC 做第二次解碼。
- SV 裡即使欄位以 `logic [7:0]` 儲存，乘法時仍必須作**正確 sign extension / `$signed(...)`**。
- C struct、SV packed union、HBM byte image **不具可直接 memcpy 相容的二進位 layout**；欄位需明確對應。

## 3. MLU：Memory Load Unit

- 來源命令：`mode`、`src_addr`、`meta.tile_id`（32-bit）及 `meta.dst_addr`（64-bit）。來源與目的地址須對齊 **32 bytes**。
- 兩個 tile buffers；命令依序載入與輸出。可同時輸出前一 tile 並預載下一 tile，但每次僅串流一個 tile 的 k=0..7。
- 需**成功交握**送出 k=7，才可以重用該 buffer；不必等待 TC 將該 tile 計算／MSU 寫回完成。
- memory request：`read_request_valid && read_request_ready`；response：`read_data_valid && read_data_ready`，每 beat 32 bytes，`read_last` 標記 burst 最後一 beat。模型限定**最多一筆 outstanding read burst**；response 有序，第一 beat 最早於 request 後下一拍。
- 先完成整個 tile 讀取後才產生八筆 DU/TIA 封包。下游阻擋時，MLU 的 `out_valid` 和 payload 必須穩定。
- `k_position = k % 4`；完整 k、tile ID、dst address 走側邊 metadata，不需改原 DU/TIA 的 ports。

### 3.1 固定 memory image layout（單位：byte）

| Mode | 有效資料 | 實際讀取 | 從 `src_addr` 起算的排列 |
|---|---:|---:|---|
| Dense | 128 B | 4 × 32 B = 128 B | 每個 k offset=`16*k`：先 A[:,k] 8B，再 B[k,:] 8B |
| Hybrid | 120 B | 4 × 32 B = 128 B | 前 72B：每個 k 放 A bitmap 1B + A packed[8] 8B；後 48B：兩個 B group，各 8 columns × (mask 1B + values 2B) |
| Dual sparse | 144 B | 5 × 32 B = 160 B | 每個 k：A bitmap 1B + A packed[8] 8B + B bitmap 1B + B packed[8] 8B |

Hybrid B group (`g∈{0,1}`) 與 column j 的 offset 是 `72 + 24*g + 3*j`；四個 k 位置對應 `k=4*g+p`。B 2:4 mask 使用低 4 bits，且必須恰好兩個 set bits（六種合法 mask）。兩個 B packed value 按 set bit 對應的 k 由小到大排列，組內重複使用資料。

A bitmap bit i 對應 row i；dual B bitmap bit j 對應 column j。unstructured value 依原 index 遞增壓入，合法資料個數由 popcount 決定。無效 padded bytes 不參與計算。這是**固定空間的 memory image**，不是可變長度極致壓縮格式。

## 4. DU/TIA：Decompression + index alignment

- 維持原本 S0/S1/S2/S3 的四級輸入到輸出寄存器管線，無 `out_ready` 回傳；以 `in_valid=0` 插 bubble。
- Dense mode 應保留原有 bypass/無稀疏解碼的路徑；Hybrid / Dual sparse 由 DU 解碼與 TIA 對齊生成 TC 所需稀疏 payload。**詳細 per-stage struct/控制邏輯以現行 RTL 與 C model 為準，勿自行重命名或重新切 stage。**
- 在 DU/TIA 外部平行四級 sideband，儲存 `valid/is_sparse/meta/k`；完整矩陣 payload 不需要從 sideband 再複製傳遞。
- 因 DU/TIA 不可停頓，需要下游 Bridge 的 credit 預留，不能只看 FIFO 當下 occupancy。

## 5. Bridge / FIFO / metadata — critical cycle-level contract

### 5.1 容量與信用額度

- `IO_PACKET_FIFO = 8`，DU/TIA sideband stages = 4，result metadata queue = 2。
- `used = fifo_count + inflight_count <= 8`，其中 `inflight_count` 包含已進 S0..S3 但尚未入 FIFO 的封包。
- `can_issue = (used < 8)`，依**舊的 register state**計算；當舊 used=8 時，即使本拍要 TC pop，也不能提前借用同拍新 credit。
- `issue` 指實際 MLU→DU/TIA handshake，issue=1 先占 1 credit；`du_valid` 抵達時 `inflight--`、`fifo_count++`（credit 總量不變）；`tc_accept` 時 `fifo_count--`、釋放 1 credit。
- 正常的 full/backpressure 是 stall；若 `can_issue=0` 卻仍 assert `issue=1`，C model 才回報 `IO_NO_CREDIT` 合約錯誤。非 `IO_OK` edge 不更新 Bridge 狀態（診斷用途，非一般 pause 機制）。
- FIFO head 為組合讀出；**無額外 head output register、無 DU→TC 同拍旁路**。

### 5.2 Edge timing

假設在 edge `t` 接受一筆 MLU 輸入：

| 時間 | 封包位置 |
|---|---|
| edge `t` | 進入 DU/TIA S0 |
| `t+1` | S1 |
| `t+2` | S2 |
| `t+3` | S3 |
| `t+4` | Bridge 從舊 S3 接受、寫入 FIFO |
| `t+5`（最早） | TC 接受 FIFO head |

**同一拍的所有 peek / handshake 必須由舊狀態計算，再讓所有模組各 tick 一次。** 不可先更新 DU，再把新 S3 當成 FIFO 同拍輸入。

### 5.3 TC strict-valid 與結果 metadata

- 目前 TC 的 `in_valid=1` 若同拍不 ready，是合約錯誤，不是標準「valid hold 等 ready」。Bridge/link 必須先將 `head_entry.packet` 持續呈現給 TC，用 mode-aware `in_ready` 決定能否設 `tc_valid`。
- `tc_valid = head_valid && tc_mode_aware_in_ready`（另依 reset gate），`tc_accept` 為實際接受事件；不可直接把 FIFO 非空當作 TC valid，也不可只看非 mode-aware 的 `input_ready`。
- 如果 head 是 k=0、metadata FIFO 已有 2 筆，則 `head_valid=0` 阻止開始新 tile。
- **TC 真正接受 k=0** 才 enqueue `{tile_id,dst_addr}`；TC result 被 **MSU 接受**（`result_accept`）時才 dequeue。不是 MLU issue k=0，也不是 MSU 完成最後 HBM write beat。
- 外部保證 tile 內 k=0..7 遞增且 metadata 一致；不要默認 Bridge 自動驗證所有序列。

## 6. Tensor Core 計算核心

### 6.1 Dense

- 8×8 **output-stationary systolic array**，一個 tile 八個 k slices，經 input skew 及相鄰 PE register 傳遞。
- Dense tile 的計算／模式切換節奏不一定有 sparse 的跨 tile overlap；以目前 TC C Model／SV 逐拍行為為準。

### 6.2 Sparse

- 外積型 sparse datapath：**multiply register → route register → accumulate**。
- Sparse packet A count/index/value × B count/index/value 決定有效乘法及最終 row/column 的累加位置；每個 tile 完成時輸出 8×8 INT32。
- TC result FIFO 有兩個 physical slots，未被下游接收的結果會保留；不能覆蓋或讓下一個 tile 破壞舊結果。
- 設計目標／先前模型行為：無停頓的 sparse 流可每 **8 cycles 開始一個新 tile**（8 packets/tile，跨 tile overlap）。這是特定 steady-state 條件，不代表端到端 writeback 每 8 cycles 必定完成。
- Dense↔Sparse 模式切換前須遵守 TC 的排空條件，不能忽略 outstanding results。Hybrid↔Dual 在 TC 端都屬 sparse，模式解碼仍在 DU/TIA 端。
- [VERIFY] 曾討論 dense 結果約在 tile 連續輸入後 cycle 22、sparse 約 cycle 10；這是先前 C/RTL 範例的相對週期說法。**不要在未比對最新版本時，將這些數字當成固定 top-level latency test。**

## 7. MSU：Memory Store Unit

- TC→MSU 接收 `TcMatrix32`（8×8 INT32）和 `IoMeta`（tile ID、destination address）。必須 `result_valid && result_ready` 才能進入 MSU 的空 result buffer。
- MSU 有兩個**完整結果** buffer；前一筆寫入受阻時，只要還有空位就可以接受新結果；保證順序不亂。
- 每 tile 256B，分八筆 **32-byte / 256-bit** row-major write beats；row `r` 地址 `dst_addr + 32*r`。
- 第 j 個 INT32 在 beat 中佔 byte `[4*j]..[4*j+3]`，**little endian**。
- 當 `write_valid && !write_ready`，地址、資料、metadata、`write_last` 必須穩定。
- `tile_done` **只在 row 7 的寫入真正被接受後**出現；TC 結果進入 MSU 不等於 HBM 寫回完成。
- 此版沒有跨 K block sum、沒有寫入 response channel；model 中 `write_ready` 表示對端接受並提交該 beat。

## 8. 測試策略與已知驗證紀錄

### 8.1 單元測試先行

建議測試組織（**示意位置，先掃描現有實際目錄**）：

```text
project_root/
  AGENTS.md
  docs/architecture.md
  C_Model/        # Golden references and known test vectors
  RTL/            # Synthesizable module sources and packages
  Testbench/      # Standalone unit TBs and system-level TB
  reports/        # Timing/area reports and comparison notes
```

獨立 unit TB 分別在 boundary 模擬上下游：
- MLU TB：模擬 memory response、DU/FIFO `ready`，測 tile packing、buffer 切換與 stall。
- Bridge TB：模擬 `issue`、固定四級 DU return、TC 接受、MSU result accept，不必例化其他真正 unit；測 credit、sideband、FIFO、metadata、reset。
- TC TB：獨立驗證 dense/sparse GEMM、mode、result FIFO、精確逐拍行為。
- MSU TB：模擬 TC result stream 與 memory `write_ready`，驗證 bytes、beats、`tile_done` 和 backpressure。
- 以上通過後再做 top-level MLU→DU/TIA→Bridge→TC→MSU 的整合。

### 8.2 從早期交付文件保留下來的紀錄（非本機最新驗證聲明）

- C 版 MLU/MSU/整合 README 記錄：MLU 120 tiles/960 packets；MSU 120 results/960 beats；C integration 474 completed tiles（加上 reset 前放棄之工作）。該交付當時執行於 GCC，**不代表目前所有 SV unit 均通過相同整合驗證**。
- Bridge 獨立 RTL README 記錄：Verilator C-equivalence 19,147 input/state rows，含 7,156 expected rejected edges、13 resets；**ModelSim/Questa 入口有腳本但當時尚未實際跑過**。
- 先前 TC RTL 有 Verilator regression 討論紀錄，但具體測試數量、工具版本與結果必須看當前 repository 的 log，不可當作最新測試結果。
- [VERIFY] 最近在 ChatGPT 討論中產出 MLU、MSU、FIFO 等 SV 程式／測試版本；**這不等於已在使用者本機完成所有 unit 回歸或全系統 RTL 整合**。
- [VERIFY] 初步 ASIC synthesis 曾提到 **約 80–83 MHz、unplaced**，尚不足以代表 post-route Fmax。需保存工具、cell library/corner、clock period、constraints、critical path、area 和 routing 階段，再判斷瓶頸。

### 8.3 本機驗證清單

1. 比對 C Model、RTL、packages 的 mode encoding、各欄位 signedness / width、memory image 和時序介面。
2. 跑 C reference 和全部單獨 unit TB；保存命令、版本、PASS/FAIL 與 seed。
3. 覆蓋 dense/hybrid/dual、合法 2:4 masks `0011/0101/0110/1001/1010/1100`、極端 INT8、0 count、stored zeros。
4. 覆蓋 FIFO full+inflight、metadata full、同拍 push/pop、wraparound、reset during in-flight、up/downstream stalls。
5. 驗證不同模式連續 tiles、sparse initiation interval 和結果順序；最後執行 end-to-end GEMM + memory writeback 比對。
6. 功能通過後再讀 synthesis timing report，針對 critical path 逐項最小化改動並重跑 regression；不可只根據生成者是 Work/Codex 推測 timing。

## 9. 原始資料與實作核對優先順序

在本機專案搜尋以下**基底名稱**（可能有 `(1)`、`(2)` 等歷史副本，需先判定哪個最新、哪個 verified）：

| 範疇 | 歷史來源檔案／關鍵名稱 |
|---|---|
| MLU | `mlu_model.c/.h`, `tb_mlu.c`, `mlu.sv`, `tb_mlu.sv` |
| DU/TIA | `du_tia*.c/.h`, `du_tia_pkg.sv`, `du_tia.sv` |
| Bridge | `du_tc_bridge.c/.h`, `du_tc_bridge_pkg.sv`, `du_tc_bridge.sv`, `tb_bridge.sv` |
| TC | `tensor_core_model.c/.h`, `tensor_core_pkg.sv`, `tensor_core.sv`, `tb_tensor_core.sv` |
| MSU | `msu_model.c/.h`, `tb_msu.c`, `msu.sv`, `tb_msu.sv` |
| Integration | `io_types.h`, `tb_pipeline.c`, possible `du_tc_bridge_link.sv`, full-system SV TB |

過去 C package 有 `make test`／`build_msvc.bat` 範例；Bridge SV package 有 `run_bridge.do` 與 `run_tests.py` 範例。**這些是歷史包的命令，不能假設你現在本機根目錄一定有這些腳本**。Codex 應先列目錄再選擇可實際執行的指令。

## 10. Codex 第一輪交接任務（建議）

先不改檔案，只做 audit：

> Read AGENTS.md and docs/architecture.md. Inspect the local repository and locate the authoritative C, RTL, testbenches, packages, vectors, and scripts. Distinguish working baseline from incomplete copies. Compare the local implementation against each stated interface/cycle contract, flag conflicts, and propose a minimal standalone regression order. Do not edit or delete files, alter expected outputs, or claim tests passed without executing them.

**往後所有對話以本機 Git 工作樹 + 可重現測試為準**；本交接內容只用來幫 Codex 更快理解背景、避免遺漏既有的設計決策。
