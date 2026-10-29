# MLU SystemVerilog：獨立單元驗證版

依據本次上傳的 `mlu_model(2).c`、`mlu_model(3).h`、`io_types(4).h` 產生。
保留原本兩個 tile buffer、單一 outstanding read burst，以及每個 tile 逐 k 輸出 8 筆的時序。
`out_packet` 直接使用既有 `du_tia_pkg::du_tia_input_t`。

## 驗證範圍

`tb_mlu.sv` 只實例化 `mlu dut`，依 C model 產生的 vectors，提供 command、記憶體回傳 beat、read request ready，以及下游 `out_ready`。
每拍直接比對 MLU 的輸出封包、meta、k、握手事件、status 與完整 buffer 狀態。
停頓也由 vectors 控制，不需要實際加入 DU/TIA、bridge/FIFO、TC 或 MSU。

`du_tia_pkg.sv` 仍需編譯，因為 MLU 輸出封包使用它的型別；引用 package 不會實例化 DU/TIA 硬體。
這版已移除 DU/TIA instance、解碼 reference、4-stage scoreboard、解碼計數與對應波形；模擬專案不再包含 `du_tia.sv`。
MLU RTL、C model 與原有 golden vectors 均維持原樣。

先完成各 unit 獨立驗證，再以另一個 top-level testbench 串接 MLU → DU/TIA → bridge/FIFO → TC → MSU。
本套件不執行局部或完整整合測試；下方接線範例供之後整合時使用。

## 先在 ModelSim 執行

解壓縮整個資料夾，在 ModelSim 的 Transcript 輸入：

```tcl
do C:/your_path/mlu_sv/run_mlu.do
```

路徑有空白時使用大括號：

```tcl
do {C:/your path/mlu_sv/run_mlu.do}
```

腳本會切換到專案資料夾、編譯、加入波形並執行測試。已附 `mlu_vectors.txt`，直接跑 SV 不需要先編譯 C。
通過時應看到：

```text
ALL PASS MLU unit C/SV: 16708 records, 145 resets, 128 rejected edges
  commands=1397 packets=10236 retired=1279
  command+retire=1 read+output=4087 full_stalls=13908 both_ready=4396
```

本次實際執行的是 Verilator；未在 ModelSim/Questa 本機實測。測試平台採一般 procedural checks，沒有 SVA、DPI、UVM 或 class。

## 檔案與編譯順序

| 檔案 | 用途 |
|---|---|
| `du_tia_pkg.sv` | 原始 package，提供封包型別；不包含 DU/TIA module instance |
| `mlu_pkg.sv` | MLU command、meta、buffer、事件與封包轉換函式 |
| `mlu.sv` | MLU RTL，top module 為 `mlu` |
| `tb_mlu.sv` | 只實例化 MLU，讀取 C vectors 並逐拍比對 MLU |
| `mlu_vectors.txt` | 已產生的完整測試向量 |
| `run_mlu.do`、`wave_mlu.do` | ModelSim 執行與波形腳本 |
| `sim.f`、`synth.f` | 模擬／MLU 合成用的來源檔順序 |
| `c_ref/` | 本次 C 來源的原樣副本，以及新增的 vector generator |
| `generate_vectors.sh`、`generate_vectors.bat` | Linux／Visual Studio Developer Command Prompt 重新產生 vectors |
| `run_verilator.sh` | Linux Verilator 編譯與模擬 |
| `logs/` | 本次 C、RTL 驗證結果 |
| `SOURCE_SHA256.txt` | 輸入 C 檔案與原始 `du_tia_pkg.sv` 的 SHA-256 |

模擬依序編譯 `du_tia_pkg.sv → mlu_pkg.sv → mlu.sv → tb_mlu.sv`。
只合成 MLU 時使用前三個檔案，排除 testbench、vectors 和 C 程式。
既有專案若已經編譯 `du_tia_pkg.sv`，只保留一份 package 定義。

## C 與 RTL 的對應

| C | SystemVerilog |
|---|---|
| `Mlu` | `mlu_state_t state_q` |
| `Mlu next` | 組合邏輯 `state_d` |
| `mlu_reset()` | `rst_n=0`，非同步低有效 reset |
| `mlu_peek()` | `peek` 組合邏輯，輸出由舊暫存器狀態決定 |
| `mlu_tick()` | `next_state` 計算，於 clock 上升緣寫入 |
| `MluEvents` | `mlu_tick_info_t tick_info`，記錄剛完成那一拍的事件 |
| `IoStatus` | `status`，組合邏輯，表示下一個上升緣的檢查結果 |
| `IoFrame.packet` | `out_packet` |
| `IoFrame.meta` | `out_meta`：`tile_id[31:0]`、`dst_addr[63:0]` |
| `IoFrame.k` | `out_k[2:0]`，範圍 0～7 |

沒有額外加 output register：`out_packet` 是從已登錄的 head buffer 與 `next_k` 組合產生。
當 `out_valid=1`、`out_ready=0` 時，head 與 k 不前進，整個 packet 和 sideband 保持不變。

`tick_info` 是觀察介面，未使用時可以不接；不要拿其中已登錄的 `packet_issued` 當成同一拍 DU/TIA 的輸入 valid，這會晚一拍。

## Port 契約

| 介面 | 訊號 | 意義 |
|---|---|---|
| Command | `command_valid`、`command_ready`、`command` | 兩者同為 1 才接收新 tile command |
| Read request | `read_request_valid`、`read_request_ready` | 發出一筆 burst 請求 |
| Read request | `read_addr[63:0]` | tile 的來源 byte address |
| Read request | `read_beats[2:0]` | 實際 beat 數 4 或 5；不是 AXI 的 length-minus-one |
| Read data | `read_data_valid`、`read_data_ready` | 兩者同為 1 才收下該 beat |
| Read data | `read_data[31:0][7:0]` | 一拍 32 bytes，共 256 bits |
| Read data | `read_last` | 最後一個 beat 必須為 1，其餘為 0 |
| DU input | `out_valid`、`out_ready` | MLU 輸出握手；`out_ready` 是 bridge credit |
| DU input | `out_packet` | 236-bit DU/TIA input packed struct |
| Sideband | `out_meta`、`out_k` | 與輸出握手同步送給 wrapper／bridge |
| Diagnostic | `status`、`tick_info` | 當拍檢查結果、上一個上升緣的事件 |

這是 C model 的簡化記憶體介面。接實際 HBM／AXI controller 時，要由 adapter 轉換請求與回傳資料；MLU 本身不含 HBM controller、AXI ID／response code／arbitration。

`read_data[0]` 對應 `read_data[7:0]`，是當前 beat 最低位址的 byte；第 b 個 beat 的第 i 個 byte 存進 `image[32*b+i]`。
請勿將整個 256-bit word 的 byte 順序反過來。

reset 時及釋放 reset 前，所有相連模組應共同處於 reset，來源端應停止送出 valid；reset 期間不要採計握手。MLU 的組合輸出維持 C `peek` 語意，例如清空後 `command_ready` 為 1。

## 保留的時序

1. Command 被接受後，對應 buffer 進入 `MLU_PENDING`。
2. 下一拍起才可能發出 read request；握手後變成 `MLU_READING`。
3. 下一拍起才接受 read data，不會在 request 接受的同一個上升緣收第一個 beat。
4. 收完最後一個 beat 且格式正確後變成 `MLU_READY`。
5. 下一拍起，若該 buffer 是 head，就輸出 k=0。
6. 每次 `out_valid && out_ready`，k 前進一次；k=7 被接受後釋放該 buffer。

所有 ready／valid 都依照舊狀態計算。兩個 buffer 都占用時，即使這拍剛好送出 k=7，`command_ready` 仍為 0，要下一拍才能使用釋放的空間。
當舊 count=1 時，可以同拍收新 command 並送完舊 tile；測試中的 `command+retire` 就是這個情況。

可同時出現一個 buffer 正在讀取，另一個 buffer 正在輸出；也可以兩個都 READY，但只有 head 會輸出。最多一個 buffer 是 READING。
兩個連續 tile 都已 READY 時，前一個 k=7 之後下一拍可以直接送下一個 k=0。

## 記憶體排列

位址都是相對於 `command.src_addr` 的 byte offset。輸入已由上游完成 sparse packing，MLU 不執行零值偵測或壓縮。

| Mode | 有效 image bytes | 傳輸 bytes／beats | 每個 k 的讀法 |
|---|---:|---:|---|
| Dense | 128 | 128／4 | `A[:,k]`：`16*k + i`；`B[k,:]`：`16*k + 8 + i` |
| Hybrid | 120 | 128／4 | A bitmap：`9*k`；A packed：`9*k + 1 + i`；B 見下方 |
| Dual sparse | 144 | 160／5 | A bitmap：`18*k`；A packed：`18*k+1+i`；B bitmap：`18*k+9`；B packed：`18*k+10+i` |

Hybrid 的 B 分兩個 K group，每個 group 有 8 個 column，每個 column 存 3 bytes：

```text
b = 72 + (k / 4) * 24 + column * 3
image[b]     = 2:4 mask
image[b + 1] = packed value[0]
image[b + 2] = packed value[1]
```

k=0～3 使用第一組 B；k=4～7 使用第二組 B。
`out_packet.k_position = k[1:0]`，由 DU/TIA 根據該位置從 group 選值。
mask 在 image 裡占 1 byte，合法值只有 `03、05、06、09、0A、0C`。
MLU 驗證完整 8 bits，確認高 4 bits 為零後，送給 DU/TIA 的 mask 才縮為 4 bits。
檢查使用包含最後一個 beat 的新 image，因此最後一拍裡的非法 mask 也會被發現。

數值維持 INT8 的原始 8-bit pattern，`80` 仍表示 −128、`FF` 仍表示 −1。
MLU 只搬資料，無須加入 C `io_signed_byte()` 的減 256 電路。沿用你的 DU/TIA 定義，packed lane 本身是 bit vector；真正做乘法時仍應以 signed 解讀。

## 之後完整整合時的 DU/TIA 與 bridge 接線

本節不在目前單元 testbench 中執行。目前 `out_ready` 由 vectors 提供；完整整合後才改由 bridge 提供。
正常、無格式錯誤的流量，wrapper 的接線關係為：

```systemverilog
assign mlu_out_ready = bridge_issue_ready;
assign issue_fire   = mlu_out_valid && mlu_out_ready;

// DU/TIA 沒有 input_ready；只在真正獲得 credit 時送進一次。
assign du_in_valid  = issue_fire;
assign du_in_packet = mlu_out_packet;

// bridge 也用同一個 issue_fire 計數／接收 sideband。
// bridge_issue = issue_fire;
// bridge_meta  = mlu_out_meta;
// bridge_k     = mlu_out_k;
```

以上是接線示意，bridge port 名稱依你之後的 bridge RTL 調整。
不要直接將 MLU `out_valid` 接到 DU/TIA `in_valid`：MLU 停頓期間會維持 valid，DU/TIA 卻會每拍收一次，造成重複輸入。
`out_meta`／`out_k` 應由 wrapper 與 DU/TIA 流水線對齊；不必加進 DU/TIA 或 TC 的資料封包。
`src_addr` 只供 MLU 發出記憶體讀取；輸出的 meta 保留 `tile_id` 與後續 MSU 要用的 `dst_addr`。

## status 與錯誤處理的範圍

`IO_OK=0`、`IO_BAD_FORMAT=2`、`IO_PROTOCOL_ERROR=3` 與 C 相同。
無效 mode、地址未 32-byte 對齊、讀／寫區間溢位、hybrid 非法 mask 屬格式錯誤；`read_last` 不符合 beat 位置屬 protocol error。
`IO_BAD_ARGUMENT` 與 `IO_NO_CREDIT` 保留 enum 值，但本 MLU RTL 不產生這兩種狀態。
RTL mode 是 2 bits，非法模式用 `2'b11` 測試；C 的任意整數 mode（例如 99）不是可直接套用的 RTL port 值。

MLU buffer 滿、或 `valid=1 && ready=0` 都只是等待，**不會報錯**。
只有實際符合握手條件時，才檢查對應輸入的格式。

為了對齊 C，當 `status != IO_OK`，MLU 的所有本地狀態在該上升緣保持原值，`tick_info` 清零。`status` 不是 sticky error register，必須在該上升緣採樣。

**C 的整個 tick 回滾，無法讓真實總線已發生的握手自動回滾。** 本 RTL 沒有用 status 改寫正常 valid／ready 時序；外部模組仍可能在錯誤那一拍觀察到握手。因此整合後將非零 status 視為系統錯誤，共同 reset MLU、記憶體回應端、DU/TIA、bridge、TC 與 MSU。不要在仍持續運作的整個系統上，直接照負向單元測試的方式修改一個輸入再 retry。
這套負向測試驗證的是 MLU 的本地拒絕行為，不是完整系統的錯誤復原協定。

## 本次驗證

2026-10-24 實際完成：

- 原始 C testbench：120 tiles、960 packets、1,312 cycles，PASS。
- 保留原 C model，不改演算法；由 `gen_mlu_vectors.c` 呼叫它產生 golden vectors。
- 120-tile 原始流量、120-tile 連續流量，以及四組不同 seed、各 256-tile 的停頓流量。
- 每拍比對 `mlu_peek` 的所有輸出、當拍 status、更新後 events，以及完整 2,900-bit MLU 狀態；包含兩個 buffer 的 320 bytes，不使用 state hash 取代。
- Directed tests：同拍 command＋tile retirement、兩槽 READY、滿槽等待、head wrap、停頓時輸出穩定、signed byte 邊界、最高合法地址與越界、錯誤 last、16 個 hybrid mask 位置的多種非法值，以及處理中 reset。
- 本次修改後，使用只含 MLU 的來源清單重新編譯並執行全部 vectors；保留全部 MLU 比對與原有覆蓋門檻。

| 覆蓋項目 | 實測數量 |
|---|---:|
| 向量紀錄，包含 reset | 16,708 |
| Reset 紀錄 | 145 |
| 預期被拒絕的錯誤拍 | 128 |
| 接受的 commands | 1,397 |
| MLU 送出的 packets | 10,236 |
| 完整送出的 tiles | 1,279 |
| 同拍新 command 與舊 tile retirement | 1 |
| 同拍接受 read data 與輸出 packet | 4,087 |
| command 因滿槽而等待的拍數 | 13,908 |
| 更新後兩個 buffer 同為 READY 的紀錄 | 4,396 |

部分 directed tests 故意在 MLU tile 尚未讀完或送完時 reset，因此 commands 不一定全數 retirement。這些 reset flush 是預期行為。
`command+retire=1` 是明確安排的一個邊界情境；其他同拍收送由 `read+output=4087` 覆蓋。這兩個計數定義不同。

未執行 FPGA／ASIC synthesis 或 place-and-route；沒有宣稱 Fmax、面積、功耗或實際 HBM 效能。
目前 buffer 是有 reset 的暫存器陣列，沒有刻意做 BRAM/SRAM inference。可先用這版當逐拍等價的功能基準。

## 重新產生與重跑

Linux：

```bash
bash generate_vectors.sh
bash run_verilator.sh
```

可指定不同隨機 seed：`bash generate_vectors.sh 12345`。先等 vectors 產生完再啟動模擬。
若 Verilator 不在 PATH，設定 `VERILATOR` 為執行檔的完整路徑。
本次使用 PyPI `verilator` 5.48.0 套件的 executable；其模擬 banner 顯示 Verilator 5.49。
此套件在本環境需額外指定 GCC PCH 與 C++20 設定，重現用法如下：

```bash
MLU_VERILATOR_MAKEFLAGS='CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_STD=-std=c++20' bash run_verilator.sh
```

Windows：開啟支援 C11 的 Visual Studio Developer Command Prompt，執行 `generate_vectors.bat`。
已附 vectors，所以只想用 ModelSim 驗證時可略過這一步。Windows `.bat` 與 ModelSim `.do` 尚未在其原生環境實測。

要輸出 VCD，ModelSim 可手動以 `+VCD` 載入 testbench；Verilator 需另加 `--trace` 編譯後才使用 `+VCD`。
一般 ModelSim 流程已使用 `log -r /*` 與 WLF 波形，不必額外產生 VCD。
