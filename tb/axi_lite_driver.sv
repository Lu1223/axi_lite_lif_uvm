// ============================================================
// UVM 验证平台 - Driver（总线主机模型）
// 时序要点（防死锁/防竞争的稳健模式）：
//   先等 READY 为 1（negedge 检查，DUT 在 posedge 更新、此时已稳定），
//   再在 negedge 置 VALID（给足建立时间），下一拍 posedge 必成交，
//   成交后直接撤 VALID，绝不再看 READY（READY 成交后归 0 会误导）。
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_driver extends uvm_driver #(axi_lite_trans);

  virtual axi_lite_if vif;

  `uvm_component_utils(axi_lite_driver)

  function new(string name = "axi_lite_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "virtual interface 未配置！请检查 test 中的 config_db::set")
  endfunction

  // ---- 主机写：地址 + 数据 -> 响应 ----
  task automatic do_write(bit [31:0] addr, bit [31:0] data, output bit [1:0] resp);
    // AW：等 READY -> negedge 置 VALID -> 保持 1.5 拍（跨 2 个 posedge，
    // 保证 DUT 无论调度顺序都采样到）-> negedge 撤
    do @(negedge vif.clk); while (!vif.awready);
    vif.awaddr = addr; vif.awvalid = 1'b1;
    @(negedge vif.clk); @(negedge vif.clk);
    vif.awvalid = 1'b0;
    // W + B：W 发出时同时置 bready（从机在 W 成交拍就回 B 响应，
    // bvalid 生命周期只有 1 拍，必须在它出现的那个 negedge 检查到）
    do @(negedge vif.clk); while (!vif.wready);
    vif.wdata = data; vif.wvalid = 1'b1;
    vif.bready = 1'b1;
    do @(negedge vif.clk); while (!vif.bvalid);
    resp = vif.bresp;
    vif.wvalid = 1'b0;
    @(negedge vif.clk); @(negedge vif.clk);
    vif.bready = 1'b0;
  endtask : do_write

  // ---- 主机读：地址 -> 数据 + 响应 ----
  task automatic do_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] resp);
    do @(negedge vif.clk); while (!vif.arready);
    vif.araddr = addr; vif.arvalid = 1'b1;
    vif.rready = 1'b1;                        // 提前置（rvalid 生命周期只有 1 拍）
    @(negedge vif.clk);                      // AR 已成交，撤地址（只等 1 拍）
    vif.arvalid = 1'b0;
    do @(negedge vif.clk); while (!vif.rvalid);   // 下一拍检查：rvalid 已置 1
    data = vif.rdata;
    resp = vif.rresp;
    @(negedge vif.clk); @(negedge vif.clk);
    vif.rready = 1'b0;
  endtask : do_read

  task run_phase(uvm_phase phase);
    axi_lite_trans tr;
    forever begin
      seq_item_port.get_next_item(tr);        // 标准 TLM 获取事务（阻塞）
      `uvm_info("DRV", $sformatf("%s addr=0x%08h data=0x%08h", tr.desc, tr.addr, tr.data), UVM_MEDIUM)
      case (tr.kind)
        axi_lite_trans::WRITE : do_write(tr.addr, tr.data, tr.resp);
        axi_lite_trans::READ  : do_read (tr.addr, tr.data, tr.resp);
        default : `uvm_error("DRV", $sformatf("未知事务类型 addr=0x%08h", tr.addr))
      endcase
      seq_item_port.item_done();              // 标准 TLM 事务完成
    end
  endtask : run_phase

endclass : axi_lite_driver
