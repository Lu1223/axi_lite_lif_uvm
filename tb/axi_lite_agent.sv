// ============================================================
// UVM 验证平台 - Agent（sequencer + driver + monitor）
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_agent extends uvm_agent;

  uvm_sequencer #(axi_lite_trans) sqr;
  axi_lite_driver   drv;
  axi_lite_monitor  mon;

  `uvm_component_utils_begin(axi_lite_agent)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
  `uvm_component_utils_end

  function new(string name = "axi_lite_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = uvm_sequencer #(axi_lite_trans)::type_id::create("sqr", this);
    drv = axi_lite_driver ::type_id::create("drv", this);
    mon = axi_lite_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 标准 TLM 连接：driver 的 seq_item_port <-> sequencer 的 seq_item_export
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : axi_lite_agent
