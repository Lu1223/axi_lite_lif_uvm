// ============================================================
// UVM 验证平台 - Env（agent + scoreboard）
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_env extends uvm_env;

  axi_lite_agent      agt;
  axi_lite_scoreboard scb;

  `uvm_component_utils(axi_lite_env)

  function new(string name = "axi_lite_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = axi_lite_agent     ::type_id::create("agt", this);
    scb = axi_lite_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // monitor 的 analysis port -> scoreboard 的 analysis imp
    agt.mon.ap.connect(scb.ap);
  endfunction

endclass : axi_lite_env
