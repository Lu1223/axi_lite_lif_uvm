// ============================================================
// UVM 验证平台 - testbench 聚合文件
// 只负责按依赖顺序 include 所有验证组件文件；
// 顶层模块在 uvm_test_top.sv 中（被本文件 include）
// ============================================================
`include "axi_lite_if.sv"
`include "axi_lite_trans.sv"
`include "axi_lite_driver.sv"
`include "axi_lite_monitor.sv"
`include "axi_lite_scoreboard.sv"
`include "axi_lite_agent.sv"
`include "axi_lite_env.sv"
`include "axi_lite_seq_lib.sv"
`include "axi_lite_test_lib.sv"
`include "uvm_test_top.sv"
