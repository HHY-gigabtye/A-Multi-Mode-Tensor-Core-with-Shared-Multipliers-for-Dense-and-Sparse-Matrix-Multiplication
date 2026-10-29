# Tensor Core：Sparse 跨 tile C model

基於本次上傳的 `tensor_core_model(2).c`、`tensor_core_model(2).h`、`tb_tensor_core(2).c` 修改。交付檔案使用原本 include 所需的標準名稱。

## 檔案與範圍

| 檔案 | 用途 |
| --- | --- |
| tensor_core_model.h | 資料結構、API、握手規則 |
| tensor_core_model.c | 逐拍 C model，沒有 main |
| tb_tensor_core.c | 原有單 tile 測試、新增連續 tile scoreboard、效能量測，唯一的 main |
| verification.txt | 編譯與執行的實際輸出，以及驗證限制 |

- 保持 INT8 × INT8 → INT32，M=N=K=8；每 8 個接受成功的封包是一個 tile。
- Sparse／外積路徑支援跨 tile 接收。DU/TIA 後的各種 sparse 格式都使用 `is_sparse=true` 的相同路徑。
- Dense systolic 路徑保持一次一個 tile；原有逐 PE 到達時序檢查保留。
- 模式切換要等所有已開始的 tile 完成、結果全部取走，`busy=false` 才能切換。
- 本次只修改 C model 和 testbench。沒有加入 DU/TIA、MLU、MSU，也沒有生成或驗證新版 RTL。
- Testbench 的 `dense-unstructured` 是直接建構解碼後封包的測試分類；它不代表新增 DU/TIA compiler mode。

## 如何運作

### 1. 讓 first／last 跟著 MUL、ROUTE 傳到 ACC

輸入不用新增 first／last 欄位；核心依接受成功的封包數，自動每 8 筆產生邊界標記。

第一筆抵達 ACC 時才清零整個累加矩陣，再加入本筆有效乘積。即使第一筆的 count=0，也會正確清零。收到下一個 tile 第一筆時，不會清掉仍在運算中的上一個 tile。

### 2. 在同一拍保存上一個結果，開始下一個累加

`finish_pending` 仍保留一拍的結果暫存階段。`tc_tick()` 先把舊 ACC 值放到結果 FIFO，才呼叫 `sparse_tick()` 更新 ACC。這讓上一個 tile 的最後乘積包含在輸出中，也避免新 tile 的 first 清零破壞結果。

在 RTL 中要保留「讀取上一拍狀態、再提交下一拍狀態」的語意，不能任意交換這兩件事的順序。

### 3. 固定兩個結果位置，開始 tile 前先預留

`result` 是 FIFO 頭，`result_next` 是第二個位置。仍只有一份 sparse 工作累加器，沒有複製第二套運算陣列。

| 欄位 | 新版含義 |
| --- | --- |
| received | Sparse：下一筆輸入的 k，0～7 循環；Dense：保留原本 0～8 計數 |
| outstanding | 已開始、結果尚未被取走的 tile 數，包含部分輸入、pipeline 內工作及完成結果，最大 2 |
| result_count | FIFO 內已完成的結果數，0～2 |
| result_valid | result_count > 0，表示 FIFO 頭可被接收 |
| busy | 還有 outstanding tile；即使 pipeline 已空、仍有結果未取走，也維持 true |

每個 tile 第一筆接受時預留一個結果位置。位置滿了，只擋住下一個 tile 的第一筆；已開始的 tile 仍可接完並排空。因此，即使 result_ready 長時間為 false，在途資料也有地方放。

`TC_RESULT_SLOTS=2` 描述的是目前明確實作的兩個位置，不能只改這個常數就擴充 FIFO。

## 時序範例

假設沒有輸入空拍，且輸出一直 ready：

| Tile | 接受輸入 | 最後一次 ACC | 結果進入 FIFO | 結果被取走 |
| --- | --- | --- | --- | --- |
| 0 | cycle 0～7 | 9 | 10 | 11 |
| 1 | cycle 8～15 | 17 | 18 | 19 |
| 2 | cycle 16～23 | 25 | 26 | 27 |

cycle 10 會同時保存 tile 0 的完整結果，並開始 tile 1 的第一筆累加。結果發布時，不會讓 MUL／ROUTE 停下來。

## 編譯與執行

### GCC

在解壓後的資料夾執行：

```bash
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror tensor_core_model.c tb_tensor_core.c -o tb_tensor_core
./tb_tensor_core
```

### Visual Studio

在同一個 C 專案使用這次的兩個 `.c` 和一個 `.h`。把舊版同名來源檔從建置中移除，避免重複函式或重複 main。`.h` 放在這兩個 `.c` 能 include 到的位置，不需要獨立編譯。

支援 C11 的 Visual Studio Developer Command Prompt 可用：

```bat
cl /std:c11 /W4 /TC tensor_core_model.c tb_tensor_core.c /Fe:tb_tensor_core.exe
tb_tensor_core.exe
```

交付前是在 Linux/GCC 上編譯驗證，沒有實際執行 Windows/MSVC。

### 顯示跨 tile 運作

```bash
./tb_tensor_core --tests 0 --stream-tiles 8 --bench-tiles 100 --stream-trace
```

Windows 執行時改用 `tb_tensor_core.exe`。`--stream-trace` 會印出 3 個滿載 sparse tile，可直接觀察 cycle 8 接收 tile 1、cycle 16 接收 tile 2。

其他參數：

| 參數 | 功能 |
| --- | --- |
| --tests N | 每種模式的原有單 tile 隨機測試數，預設 1000，允許 0 |
| --stream-tiles N | 每組隨機串流測試的 tile 數，預設 1000，至少 1 |
| --bench-tiles N | 滿載效能測試的 tile 數，預設 100，至少 1 |
| --seed N | 隨機種子；0 會使用固定替代種子 |
| --demo / --trace / --bubbles | 保留原有單 tile 範例、時序追蹤與輸入空拍選項 |
| --mode all/dense/hybrid/dual/dense-unstructured | 只篩選原有單 tile 測試；跨 tile 與回歸測試仍會執行 |

## 呼叫 API 時要注意

1. 建議用 `tc_input_ready_for(&core, next_packet.is_sparse)` 判斷下一個封包能否送入。`tc_input_ready()` 仍保留，但只表示目前模式的接收能力；它不替下一個封包判斷模式相容性。
2. 下一個封包不能送時，保留它，這一拍仍呼叫 `tc_tick(..., false, NULL, result_ready, ...)`，讓 pipeline 與輸出繼續前進。不要因為 input_ready=false 就停止呼叫 tc_tick。
3. 延續舊版的嚴格 API：在 not-ready 時提供有效輸入，會回傳 TC_NOT_READY，整次呼叫不前進。它不是硬體上「valid 保持為 1、等待 ready」的自動處理；driver 必須依 readiness 決定是否把封包交給模型。
4. 結果若要在這一拍被取走，必須在呼叫 tc_tick **之前**讀取／保存 `core.result`。呼叫後 FIFO 頭可能已經換成下一個結果。testbench 的 run_stream() 有完整範例。
5. 同一拍可能一邊接收 sparse 輸入、一邊輸出結果；也支援 FIFO 舊結果取走與新結果發布在同一拍發生。
6. 回收的結果容量在下一次 readiness 查詢才可使用，不建立從當拍 result_ready 到 input_ready 的直通邏輯。理想無阻塞串流仍可每拍接收。
7. 所有 tile 按輸入順序輸出，沒有重新排序。固定 8 筆構成一個 tile；空 sparse 向量也算一筆有效封包，不能直接跳過而不調整協定。

## 利用率量測

條件：固定 64 MAC/cycle 作為峰值容量；每個 sparse 封包 A、B 各有 8 個合法、非零的有效值，索引 0～7；100 個 tile；輸入沒有額外空拍；輸出一直 ready；所有結果和獨立的矩陣乘法 golden 比對。

| 排程 | 總週期 | 有效 MAC | 利用率 |
| --- | --- | --- | --- |
| 一個 tile 的結果取走後才送下一個 | 1200 | 51200 | 66.6667% |
| Sparse 跨 tile 連續輸入 | 804 | 51200 | 99.5025% |

利用率 = MAC 總數 / (64 × 總週期)。計時從第一筆輸入那一拍開始，到最後一個結果被取走那一拍結束，**包括整批起始與收尾**。持續模式 N 個 tile 為 8N+4 拍；單 tile 仍為 12 拍，提升的是持續吞吐，第一個結果的延遲沒有縮短。

同一個 testbench 用相同種子和資料，分別以 serial 與 overlap 排程執行。原有測試仍用 run_tile() 檢查單 tile 功能，新 run_stream() 才會主動送入下一個 tile。

99.50% 是核心 C model 的滿載測試結果，不是所有 sparse 資料的利用率，也不是已完成 RTL 合成的 TOPS 數字。每筆有效元素較少、模式切換、輸出阻塞與外部供應不足，都會降低整段利用率。資料格式名稱 sparse 不代表測試一定含零；這裡刻意使用該介面允許的滿載向量測量最佳情況。DU/TIA 與記憶體供應不包含在此測試中。

## 驗證涵蓋

- 原有四種解碼後資料分類的 directed/random 測試與逐 PE dense 到達時序。
- 獨立 i/j/k GEMM golden 檢查每個輸出矩陣，以及輸出順序。
- Sparse first／last 穿越 tile 邊界，含全零 tile、空的第一筆／最後一筆、儲存的零值及 INT8 極值。
- 輸入隨機空拍、輸出長時間阻塞、兩個結果位置滿載、信用額度回收。
- 同一拍取走舊結果並發布新結果；同一拍取走舊結果並接收新 tile 第一筆。
- Sparse 各種資料格式連續切換，以及 dense/sparse 等待排空後切換，過程不 reset。
- 原有 48 個 reset/restart 時點，加上 30 個包含重疊工作和未取走結果的 reset 時點。
- 錯誤輸入拒絕時不修改狀態，包括模式錯誤、count/index 錯誤及沒有結果容量。

預設測試共通過 6389 個 tile。AddressSanitizer 與 UndefinedBehaviorSanitizer 檢查通過；LeakSanitizer 因執行環境限制停用。另以 NDEBUG 編譯並更換種子，確認功能不依賴 assert 的執行。詳細命令和實際輸出見 verification.txt。
