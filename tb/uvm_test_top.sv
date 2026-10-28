// ============================================================
// UVM 验证平台 - 顶层模块
// 时钟/复位生成 + DUT 例化 + interface 连接 + run_test
// ============================================================
`timescale 1ns / 1ps

module uvm_test_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---- 时钟 ----
  logic clk  = 0;
  always #5 clk = ~clk;              // 100 MHz

  // ---- interface 与 DUT 连接 ----
  axi_lite_if vif(clk);

  axi_lite_lif_reg_slave dut (
    .clk(clk), .rstn(vif.rstn),      // 注意：接 vif.rstn（复位时序驱动的是它，接模块级 rstn 会永远复位）
    .s_axi_awaddr(vif.awaddr), .s_axi_awvalid(vif.awvalid), .s_axi_awready(vif.awready),
    .s_axi_wdata(vif.wdata),   .s_axi_wvalid(vif.wvalid),   .s_axi_wready(vif.wready),
    .s_axi_wstrb(4'hF),              // DUT 有 wstrb 端口，之前漏连了
    .s_axi_bresp(vif.bresp),   .s_axi_bvalid(vif.bvalid),   .s_axi_bready(vif.bready),
    .s_axi_araddr(vif.araddr), .s_axi_arvalid(vif.arvalid), .s_axi_arready(vif.arready),
    .s_axi_rdata(vif.rdata),   .s_axi_rresp(vif.rresp),     .s_axi_rvalid(vif.rvalid),
    .s_axi_rready(vif.rready),
    .lif_thresh(vif.lif_thresh), .lif_leak(vif.lif_leak),
    .spike_count(vif.spike_count)
  );

  // ---- 配置 virtual interface -> 启动 UVM 测试 ----
  // 注意：run_test 必须在 0 时刻调用（UVM 1.2 要求 run phase 从 0 开始），
  // 复位等待必须放到独立的 initial 块里，否则报 RUNPHSTIME 致命错误
  initial begin
    vif.rstn        = 0;
    vif.spike_count = 32'hDEAD_BEEF;   // 模拟 LIF 核维护的计数值

    // 把 virtual interface 放入 config_db（所有组件可见）
    uvm_config_db#(virtual axi_lite_if)::set(null, "*", "vif", vif);
    run_test("reg_rw_test");
  end

  // ---- 复位序列（独立于 run_test，避免 run phase 非 0 时刻启动） ----
  initial begin
    repeat (10) @(posedge clk);
    vif.rstn = 1;
  end

  // ---- 仿真时长保护：超时强制结束 ----
  initial begin
    #50us;
    $display("[TIMEOUT] simulation watchdog triggered");
    $finish;
  end

endmodule : uvm_test_top
