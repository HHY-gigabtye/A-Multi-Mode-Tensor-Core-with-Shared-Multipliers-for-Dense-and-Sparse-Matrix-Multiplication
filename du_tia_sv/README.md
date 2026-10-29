# DU + TIA SystemVerilog RTL — No-Assertion Version

這一版專為不支援 SystemVerilog Assertions 的 ModelSim–Intel FPGA Edition
準備。RTL、testbench、filelist 與建置流程中都沒有 `assert property`、SVA
checker、coverage property 或 `--assert` 選項。

## 內容

| 檔案 | 用途 |
|---|---|
| `rtl/du_tia_pkg.sv` | 精簡後的型別、packed union 與 helper functions |
| `rtl/du_tia.sv` | 不含 assertion 的四級 DU/TIA pipeline |
| `tb/tb_du_tia.sv` | golden model、scoreboard 與 3292 筆功能測試 |
| `filelist.f` | package、RTL、TB 的編譯順序 |
| `modelsim.do` | ModelSim 編譯及執行腳本 |
| `Makefile` | Verilator lint、simulation 與 VCD |

`verification/du_tia_sva.sv` 已從本版本移除。TB 仍會利用逐筆 expected packet
比較與 `$fatal` 回報錯誤，但這不是 SVA，也不會加入正式硬體。

## 精簡後的正式資料路徑

- `transaction_id`：不存在於 DUT packet 或 stage registers。
- `du_action`、`tia_action`：不存在；S1 直接依 `mode` 選擇運算。
- `b_source_rank`：只在 S1 組合選值時即時計算，不註冊、不輸出。
- `bitmap`：只用於輸入與 S1 組合解碼，不往後傳。
- `valid_mask`：刪除，以 `count` 表示有效 packed prefix。
- `count`：保留，讓下游知道 value/index 的有效筆數。
- `index`：每筆 3 bits，表示 lane 0–7。

介面寬度：

| 型別 | 寬度 |
|---|---:|
| `du_tia_input_t` | 236 bits |
| `du_tia_output_t` | 185 bits |
| S0–S3 registers 合計 | 807 bits |

## ModelSim 使用方式

在 Transcript 先切換到包含本 README 的專案根目錄，再執行：

```tcl
do modelsim.do
```

或者手動執行：

```tcl
vlib du_tia_work
vmap du_tia_work du_tia_work
vlog -work du_tia_work -sv rtl/du_tia_pkg.sv
vlog -work du_tia_work -sv rtl/du_tia.sv
vlog -work du_tia_work -sv tb/tb_du_tia.sv
vsim du_tia_work.tb_du_tia
run -all
```

預期結尾：

```text
[PASS] DU/TIA compact RTL: 3292 packets checked
```

如果只要編譯 DUT，不需要 TB：

```tcl
vlog -work work -sv rtl/du_tia_pkg.sv
vlog -work work -sv rtl/du_tia.sv
```

這一版不需要加入 `+define+SYNTHESIS`，因為 assertion 原始碼已實際移除。

## Verilator

```bash
make lint
make sim
```

或：

```bash
make all
```

TB 預設檢查 12 筆 directed、24 筆 Ux2:4 exhaustive、256 筆 UxU bitmap
exhaustive，以及 3000 筆 randomized packets。
