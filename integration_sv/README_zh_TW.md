# Sparse Tensor Core 整合（SystemVerilog / ModelSim）

本目錄新增可綜合的 `sparse_tensor_core_top` 與純 SV 整合 testbench，直接使用現有五個元件。
未修改既有 RTL、package、testbench、向量或 C reference，也沒有新增／編譯 C 程式。

## 檔案與連接

| 新增檔案 | 用途 |
|---|---|
| `rtl/sparse_tensor_core_top.sv` | 整合 top，正式設計來源 |
| `tb/tb_sparse_tensor_core_top.sv` | SV 記憶體模型、矩陣產生器、GEMM scoreboard、逐拍與 reset 檢查 |
| `sim/run_top.do` | 編譯、模擬 top；GUI 下同時加入波形 |
| `sim/wave_top.do` | 波形分組 |
| `sim/run_units.do` | 在隔離 library 中執行五個原有 SV 單元測試 |
| `sim/run_regression.ps1` | 可選的批次啟動器，檢查 exit code、錯誤與所有 PASS 標記 |
| `results/units.log`、`results/top.log` | 本機 ModelSim 實際執行紀錄 |
| `results/VALIDATION.md` | 驗證摘要、命令與限制 |

```text
command / read memory
          |
         MLU -- issue = out_valid && can_issue --> DU/TIA
          |                                        |
          +-- mode / k / metadata --> Bridge <-----+
                                     |
                       packet FIFO (8), inflight credit,
                       4-stage sideband, result metadata (2)
                                     |
                       head_valid && TC.in_ready
                                     |
                                Tensor Core
                                     |
                         result + ordered metadata
                                     |
                                    MSU
                                     |
                         write memory / tile_done
```

top 不再建立第二份 sideband；現有 `du_tc_bridge` 已包含四級 tags。
不同 package 的 payload 和 metadata 逐欄位對接，避免依賴跨 package struct 的隱含布局。
DU/TIA 輸出兩種 sparse 模式都用 `is_sparse=1`。

Bridge 使用舊狀態的 `fifo_count + inflight_count < 8` 放行 MLU。
FIFO head 始終呈現給 TC，使用 **mode-aware `in_ready`** 才產生 TC 的 `in_valid`。
metadata 在 TC 接受 k=0 時入列，在 TC→MSU 真正交握時出列。
沒有新增資料暫存級、旁路、跨 tile 累加或全域控制狀態機。

## Top 外部介面

| 介面 | 契約 |
|---|---|
| `clk`, `rst_n` | 共用 clock、低有效非同步 reset；reset 時須一起取消外部 pending memory response |
| `command_valid/ready`, `command` | `mlu_pkg::io_command_t`，mode、64-bit source、32-bit tile ID、64-bit destination；valid 等待期間命令保持穩定 |
| `read_request_valid/ready`, `read_addr`, `read_beats` | 一次最多一筆 outstanding burst；`read_beats` 是實際 4 或 5 beats，非 AXI ARLEN |
| `read_data_valid/ready`, `read_data`, `read_last` | 每 beat 256 bits，byte 0 在 `[7:0]`；第一 beat 最早在 request 接受後下一拍 |
| `write_valid/ready`, `write_addr/data/last/meta` | 每 tile 八個 256-bit row beats；row-major、INT32 little endian；stall 時保持穩定 |
| `tile_done`, `completed` | row 7 實際寫入接受後的 registered pulse 與 metadata；非 TC 計算完成通知 |
| `mlu_status`, `bridge_status`, `tc_status`, `msu_status` | 各元件原有診斷碼；合法流量皆為 0 |

每個 command 為獨立 8×8×8 signed INT8→INT32 GEMM。mode 0/1/2 分別為 dense、hybrid、dual；mode 3 非法。
Source/destination 均須 32-byte 對齊，並符合既有模組的完整 burst／結果地址範圍檢查。
Source image 沿用 `docs/architecture.md` 的 128B dense、128B padded hybrid、160B padded dual 格式。
這是原有的簡化讀寫介面，沒有 AXI/HBM response、跨 K tile accumulation 或讀寫仲裁。
非零 status 是介面錯誤；top 沒有加入交易回復機制，須修正來源並一起 reset。

## ModelSim 使用

從 repository 根目錄啟動，直接驗證 top（不需要 C compiler 或外部 golden 檔案）：

```powershell
Set-Location C:\Users\Jason\Desktop\TC
vsim -c -l integration_sv/results/top.log -do integration_sv/sim/run_top.do
```

GUI 的 Transcript 執行：

```tcl
cd C:/Users/Jason/Desktop/TC
do integration_sv/sim/run_top.do
```

腳本會加入波形並停在測試結束處。`integration_sv/build/top/vsim.wlf` 是執行產生的波形檔。
若從其他位置呼叫絕對路徑的 `.do`，先設定：

```tcl
set env(STC_ROOT) C:/Users/Jason/Desktop/TC
do C:/Users/Jason/Desktop/TC/integration_sv/sim/run_top.do
```

ModelSim 2020.1 的 `do` 巨集中 `[info script]` 並不可靠；本腳本由目前目錄向上尋找 repository，或使用 `STC_ROOT`。
所有 build/library 都放在 `integration_sv/build/`，不覆寫各單元原來的 library。

重跑既有 SV 單元測試：

```powershell
vsim -c -l integration_sv/results/units.log -do integration_sv/sim/run_units.do
```

可選的完整回歸入口：

```powershell
& .\integration_sv\sim\run_regression.ps1
# 僅整合：
& .\integration_sv\sim\run_regression.ps1 -TopOnly
```

所有 stimulus、記憶體模擬、矩陣比對都在 SV。
既有 MLU／Bridge／TC／MSU 單元 TB 仍讀取它們原本的 C 產生向量；不修改、不重新產生。
`run_units.do` 在 `$finish` 後繼續下一個測試；自動化建議用 PowerShell 入口確認五個 PASS 標記和無 Fatal/Error。
`run_top.do` 自行檢查 TB 的 `passed`，未到 PASS 的 batch 執行會回傳非零 exit code。

編譯順序見 `sim/run_top.do`：各 package 在 module 之前，top 在五個 module 之後。
整合只編譯 `du_tia_sv/rtl/du_tia_pkg.sv` 與 `tensor_core_sv/tensor_core_pkg.sv` 各一份，
不重複編譯 MLU、FIFO 目錄下的同名 package。

## 驗證內容

TB 從原始數學 A/B 矩陣計算 GEMM，再獨立編碼記憶體 image；不用 DUT 的 packetize／decode helper 產生預期值。
除了每個 INT32 結果，還比對每個寫出 byte、地址、tile ID、k 順序和完成通知。

- 64-tile 無 stall sparse 串流，逐個相鄰 tile 驗證 II=8；96-tile 混合模式與 48-tile sparse 壓力流。
- 全部九種 mode→mode 切換、六種合法 2:4 mask、-128／127／0／±1、zero/full count、合法 stored zero。
- command/request gaps、response latency 與 gaps、長時間 write backpressure、last-beat stall。
- issue→DU 到達恰四拍；issue→TC 最早五拍；禁止 FIFO empty bypass 和 full credit lookahead。
- 每拍檢查 FIFO、inflight、metadata 計數更新；同拍 push/pop、wrap、metadata full、MSU full、TC result full。
- TC k=7 接受後 sparse 第 3 個後續 edge、dense 第 15 個後續 edge 發布結果（目前 SV 實測契約）；stall 時結果／metadata 保持穩定。
- reset 前逐一達到 FIFO 0…8、inflight 0…4、metadata／MSU／TC result／MLU buffer 0…2，及寫回 row 0…7；另測 outstanding read 與 stalled last beat。
- 每次受測 reset 會清除模擬記憶體的未完成 response，再用新 tile ID 執行三個 recovery tiles，確認沒有舊封包／結果漏出。

這些是固定 seed 的動態模擬與 directed coverage，不是 formal proof。10 ns TB clock 僅供模擬排程，不代表 100 MHz timing closure。
此次未執行 synthesis、placement、routing 或 PPA 量測。
