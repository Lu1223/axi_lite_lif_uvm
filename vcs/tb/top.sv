// ============================================================================
// top.sv —— 测试平台顶层（tb_top）
// ----------------------------------------------------------------------------
// 职责：
//   1. 生成时钟（100MHz）与复位（低 100ns 后释放）
//   2. 例化 interface 和 DUT，完成信号连线
//   3. 驱动 LIF 侧 spike_count（真实系统中由 LIF 核更新，这里 TB 给常量）
//   4. 把 virtual interface 放进 config_db（UVM 全局配置数据库）
//   5. 导出 FSDB 波形（Verdi 查看）
//   6. 启动 UVM 测试：run_test() 会根据命令行 +UVM_TESTNAME=xxx 创建测试
//   7. 看门狗：防止仿真挂死
// ============================================================================
module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi_lite_pkg::*;

  // ------------------- 时钟与复位 -------------------
  logic clk;
  logic rstn;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;          // 周期 10ns = 100MHz
  end

  initial begin
    rstn = 1'b0;                    // 复位 10 拍（100ns）
    repeat (10) @(posedge clk);
    rstn = 1'b1;
  end

  // ------------------- interface 与 DUT -------------------
  axi_lite_if vif (clk, rstn);

  // spike_count：模拟 LIF 核输出的脉冲计数，本 TB 固定为常量
  // （scoreboard 以此值预测 0x08 读回数据；真实项目中由 LIF 核驱动）
  initial begin
    vif.spike_count = 32'hA5A5_1234;
  end

  axi_lite_lif_reg_slave dut (
    .clk            (clk),
    .rstn           (rstn),
    // 写地址通道
    .s_axi_awaddr   (vif.awaddr),
    .s_axi_awvalid  (vif.awvalid),
    .s_axi_awready  (vif.awready),
    // 写数据通道
    .s_axi_wdata    (vif.wdata),
    .s_axi_wstrb    (vif.wstrb),
    .s_axi_wvalid   (vif.wvalid),
    .s_axi_wready   (vif.wready),
    // 写响应通道
    .s_axi_bresp    (vif.bresp),
    .s_axi_bvalid   (vif.bvalid),
    .s_axi_bready   (vif.bready),
    // 读地址通道
    .s_axi_araddr   (vif.araddr),
    .s_axi_arvalid  (vif.arvalid),
    .s_axi_arready  (vif.arready),
    // 读数据通道
    .s_axi_rdata    (vif.rdata),
    .s_axi_rresp    (vif.rresp),
    .s_axi_rvalid   (vif.rvalid),
    .s_axi_rready   (vif.rready),
    // LIF 侧
    .lif_thresh     (),
    .lif_leak       (),
    .spike_count    (vif.spike_count),
    .lif_en         ()              // 场景4新增：悬空即可，波形里看 dut.en_reg
  );

  // ------------------- UVM 启动 + FSDB 波形 -------------------
  initial begin
    // 波形导出：全层级、全信号（Verdi 用 simv.fsdb 查看）
    $fsdbDumpfile("simv.fsdb");
    $fsdbDumpvars(0, tb_top, "+all");

    // virtual interface 放入 config_db，通配 "*" 让所有 UVM 组件可见
    uvm_config_db #(virtual axi_lite_if)::set(null, "*", "vif", vif);

    // 启动测试（+UVM_TESTNAME=xxx 在 Makefile/命令行指定）
    run_test();
  end

  // ------------------- 看门狗：500us 未结束视为挂死 -------------------
  initial begin
    #500_000ns;
    `uvm_fatal("TB", "WATCHDOG TIMEOUT: simulation stuck > 500us!")
  end

endmodule : tb_top
