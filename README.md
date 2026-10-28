# AXI-Lite LIF 寄存器从机 UVM 验证

基于 UVM 1.2 的 AXI4-Lite 从机寄存器配置模块验证平台，覆盖寄存器读写、只读保护、非法地址响应等场景。**ModelSim ASE 与 VCS 双工具链均跑通，18 PASS / 0 FAIL（ModelSim）+ 7 测试全 PASS（VCS）。**

## 项目背景

DUT 为 SNN（脉冲神经网络）FPGA 项目中 **LIF（Leaky Integrate-and-Fire）神经元核的寄存器配置接口**，实现 PS 通过 AXI-Lite 总线配置 PL 侧神经元参数的典型场景。

## DUT 功能

`rtl/axi_lite_lif_reg_slave.sv` —— AXI4-Lite 从机，五通道握手（AW/W/B/AR/R），支持：

| 偏移 | 寄存器 | 属性 | 说明 |
|---|---|---|---|
| 0x00 | LIF_THRESH | RW | 阈值（Q16.16 定点，默认 65536 = 1.0） |
| 0x04 | LIF_LEAK | RW | 泄漏系数（Q16.16，默认 58982 = 0.9） |
| 0x08 | SPIKE_COUNT | RO | 脉冲计数（LIF 核维护，PS 只读） |

- 非法地址（>= 0x0C）读写均回 **SLVERR**
- 写通道独立状态机（AW→W→B），读通道独立状态机（AR→R）
- 内嵌 5 组 **SVA 断言**（握手超时 / W 不早于 AW / 非法地址必回 SLVERR / BVALID·RVALID 稳定性 / 复位默认值），`+define+USE_SVA` 启用

## 验证环境

```
uvm_test_top（顶层：clk/rst 生成 + DUT 例化 + vif 连接 + run_test）
└── base_test
    └── axi_lite_env
        ├── axi_lite_agent
        │   ├── axi_lite_driver   —— 驱动 AXI-Lite 事务（start_item/finish_item）
        │   ├── axi_lite_monitor  —— 采样总线事务 → 送 scoreboard
        │   └── sequencer
        └── axi_lite_scoreboard   —— 参考模型 + 自动比对（写-读一致性/只读保护/SLVERR）
```

标准 UVM 分层：`axi_lite_if`（interface）→ `axi_lite_trans`（事务）→ driver/monitor/scoreboard → agent/env → seq_lib/test_lib。

## 测试用例（T1–T5）

| 编号 | 场景 | 检查点 |
|---|---|---|
| T1 | 复位默认值 | 读 0x00=65536、0x04=58982 |
| T2 | 正常写读 | 写 0x00/0x04 后读回一致 |
| T3 | 只读保护 | 写 0x08 被忽略，读回 spike_count |
| T4 | 非法地址 | 读写 0x100 必须回 SLVERR |
| T5 | 背靠背连续读写 | 连续多笔无丢拍 |

## 双工具链版本

| 版本 | 目录 | 工具 | 结果 |
|---|---|---|---|
| ModelSim 版 | `rtl/` `tb/` `sim/` | ModelSim ASE 10.5b + UVM 1.2 源码编译 | **18 PASS / 0 FAIL** |
| VCS 版 | `vcs/` | VCS 2023.12-SP2（VM 环境，EDA 主流工具链） | **7 测试全 PASS**（reset_default / reg_rw / ro_protect / illegal_addr / en_rw / boundary / random_regression） |

## 快速开始

### ModelSim 版（Windows 本地）

1. 编辑 `sim/run_uvm.bat` 顶部两个路径，指向你的 ModelSim 安装位置：
   ```bat
   set "MSIM=<ModelSim安装目录>\win32aloem"
   set "UVM_SRC=<ModelSim安装目录>\verilog_src\uvm-1.2\src"
   ```
2. 双击 `sim/run_uvm.bat` —— 自动完成：编译 UVM 库（首次 1-2 分钟，之后缓存）→ 编译 DUT → 编译 TB → 仿真 → 汇总 PASS/FAIL
3. 波形：双击 `sim/run_wave.bat`（需先跑完步骤 2，打开 AXI 五通道 + DUT 内部信号波形）

### VCS 版（虚拟机环境）

```bash
# VM 侧（工作区 ~/eda_sim/uvm_axi_sim）
make compile && make run_all    # 编译 + 7 测试
make cov                        # 覆盖率报告
# 或 Windows 侧一键：vcs/run_vcs.bat（SSH 到 VM 自动执行并回传日志）
```

## 目录结构

```
axi_lite_lif_uvm/
├── rtl/                    # DUT：AXI-Lite LIF 寄存器从机
│   ├── design.sv                     # 编译入口（include DUT）
│   └── axi_lite_lif_reg_slave.sv     # DUT（含 SVA 断言，USE_SVA 开关）
├── tb/                     # UVM 验证环境（EDA Playground 风格聚合编译）
│   ├── testbench.sv                  # include 顺序聚合文件
│   ├── uvm_test_top.sv               # 顶层：clk/rst + DUT 例化 + run_test
│   ├── axi_lite_if.sv                # AXI-Lite interface
│   ├── axi_lite_trans.sv             # 事务类
│   ├── axi_lite_driver.sv            # 驱动器（start_item/finish_item 流控）
│   ├── axi_lite_monitor.sv           # 采样器
│   ├── axi_lite_scoreboard.sv        # 计分板（参考模型 + 自动比对）
│   ├── axi_lite_agent.sv             # agent（driver+monitor+sequencer）
│   ├── axi_lite_env.sv               # 环境
│   ├── axi_lite_seq_lib.sv           # 序列库（T1-T5）
│   └── axi_lite_test_lib.sv          # 测试库
├── sim/                    # ModelSim 仿真脚本
│   ├── run_uvm.bat                   # 一键编译+仿真+结果汇总
│   ├── run_wave.bat                  # 波形查看
│   └── scripts/                      # 4 个 do 脚本（批量仿真/波形配置）
└── vcs/                    # VCS 版（与 ModelSim 版同一 DUT，TB 精简为标准 pkg 结构）
    ├── rtl/  tb/                     # DUT + UVM 环境（pkg 风格）
    └── run_vcs.bat                   # SSH 到 VM 一键编译+7 测试+日志回传
```

## 技术要点

- **EDA Playground 聚合编译风格**：ModelSim 版按 include 依赖顺序组织（`testbench.sv` 聚合 9 个组件文件），兼容免费在线仿真平台
- **UVM 1.2 时序约束**：`run_test()` 必须在 0 时刻调用（否则 RUNPHSTIME 致命错误），复位序列放独立 initial 块
- **SVA 开关设计**：断言默认关闭（ModelSim ASE 免费 license 不支持断言仿真），换 Questa/VCS 时 `+define+USE_SVA` 一键启用
- **参考模型比对**：scoreboard 内置黄金参考模型，写-读一致性、只读写忽略、SLVERR 响应逐笔自动检查

## 环境要求

| 工具 | 版本 | 用途 |
|---|---|---|
| ModelSim ASE | 10.5b+ | 本地编译仿真（免费版） |
| VCS | 2023.12-SP2 | 虚拟机 EDA 标准工具链 |
| UVM | 1.2 | 验证方法学库 |
