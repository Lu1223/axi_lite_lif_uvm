// ============================================================
// UVM 验证平台 - Test 库
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class base_test extends uvm_test;

  axi_lite_env env;

  `uvm_component_utils(base_test)

  function new(string name = "base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_lite_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass : base_test

// ---- 寄存器读写测试（T1-T5） ----
class reg_rw_test extends base_test;

  `uvm_component_utils(reg_rw_test)

  function new(string name = "reg_rw_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    reg_rw_seq seq;
    phase.raise_objection(this);
    seq = reg_rw_seq::type_id::create("seq");
    seq.start(env.agt.sqr);      // 标准 sequence 启动方式
    phase.drop_objection(this);
  endtask : run_phase

endclass : reg_rw_test
