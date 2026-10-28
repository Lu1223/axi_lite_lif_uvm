// ============================================================
// UVM 验证平台 - Monitor（被动采样总线事务）
// 监视 AW/W/B 与 AR/R 握手完成，将观察到的事务经 analysis port
// 广播给 scoreboard
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_monitor extends uvm_monitor;

  virtual axi_lite_if vif;
  uvm_analysis_port #(axi_lite_trans) ap;

  `uvm_component_utils(axi_lite_monitor)

  function new(string name = "axi_lite_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "virtual interface 未配置！")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      begin : mon_write
        bit [31:0] awaddr_c;
        bit [31:0] wdata_c;
        axi_lite_trans tr;
        forever begin
          // 分阶段捕获（posedge 采样，与 DUT 采样边一致，避免与 driver 的 negedge 驱动竞态）：
          // 1) AW 握手取地址 -> 2) W 握手取数据 -> 3) B 取响应
          do @(posedge vif.clk); while (!(vif.awvalid && vif.awready));
          awaddr_c = vif.awaddr;

          do @(posedge vif.clk); while (!(vif.wvalid && vif.wready));
          wdata_c = vif.wdata;

          do @(posedge vif.clk); while (!vif.bvalid);
          tr = axi_lite_trans::type_id::create("tr");
          tr.init(axi_lite_trans::WRITE, awaddr_c, wdata_c, "mon_write");
          tr.resp = vif.bresp;
          ap.write(tr);
        end
      end : mon_write
      begin : mon_read
        bit [31:0] araddr_c;
        axi_lite_trans tr;
        forever begin
          do @(posedge vif.clk); while (!(vif.arvalid && vif.arready));
          araddr_c = vif.araddr;

          do @(posedge vif.clk); while (!vif.rvalid);
          tr = axi_lite_trans::type_id::create("tr");
          tr.init(axi_lite_trans::READ, araddr_c, 32'h0, "mon_read");
          tr.data = vif.rdata;
          tr.resp = vif.rresp;
          ap.write(tr);
        end
      end : mon_read
    join
  endtask : run_phase

endclass : axi_lite_monitor
