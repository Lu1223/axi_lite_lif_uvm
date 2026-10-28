// ============================================================================
// axi_lite_test_lib.sv —— 测试用例库
// ----------------------------------------------------------------------------
// UVM 测试的分层思路：base_test 搭好平台骨架（env），派生 test 只做一件事——
// 通过 config_db 给 sequencer 指定 default_sequence。换测试 = 换 sequence。
//
// 5 个测试用例：
//   test_reset_default      复位默认值检查
//   test_reg_rw             寄存器读写
//   test_ro_protect         只读寄存器写保护
//   test_illegal_addr       非法地址 → SLVERR
//   test_random_regression  随机混合回归（200 笔，含覆盖率收集）
// ============================================================================
`ifndef AXI_LITE_TEST_LIB_SV
`define AXI_LITE_TEST_LIB_SV

// ----------------------------------------------------------------------------
// 基类测试：创建 env、传递 virtual interface、打印拓扑与汇总
// ----------------------------------------------------------------------------
class axi_lite_base_test extends uvm_test;

  axi_lite_env       env;
  virtual axi_lite_if vif;

  `uvm_component_utils(axi_lite_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_lite_env::type_id::create("env", this);
    // 拿 top 层放进 config_db 的 virtual interface
    if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "No virtual interface found in config_db")
    // 往下广播给 env 子树的所有组件（agent/driver/monitor/scb/cov）
    uvm_config_db #(virtual axi_lite_if)::set(this, "env.*", "vif", vif);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info("TEST", "==== UVM topology ====", UVM_NONE)
    uvm_top.print_topology();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (uvm_report_enabled(UVM_NONE, UVM_INFO, "TEST_SUMMARY"))
      `uvm_info("TEST_SUMMARY", "Simulation finished", UVM_NONE)
  endfunction

endclass : axi_lite_base_test


// ----------------------------------------------------------------------------
// 1. 复位默认值检查
// ----------------------------------------------------------------------------
class test_reset_default extends axi_lite_base_test;

  `uvm_component_utils(test_reset_default)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_reset_default::type_id::get());
  endfunction

endclass : test_reset_default


// ----------------------------------------------------------------------------
// 2. 寄存器读写
// ----------------------------------------------------------------------------
class test_reg_rw extends axi_lite_base_test;

  `uvm_component_utils(test_reg_rw)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_reg_rw::type_id::get());
  endfunction

endclass : test_reg_rw


// ----------------------------------------------------------------------------
// 3. 只读寄存器写保护
// ----------------------------------------------------------------------------
class test_ro_protect extends axi_lite_base_test;

  `uvm_component_utils(test_ro_protect)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_ro_protect::type_id::get());
  endfunction

endclass : test_ro_protect


// ----------------------------------------------------------------------------
// 4. 非法地址访问
// ----------------------------------------------------------------------------
class test_illegal_addr extends axi_lite_base_test;

  `uvm_component_utils(test_illegal_addr)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_illegal_addr::type_id::get());
  endfunction

endclass : test_illegal_addr


// ----------------------------------------------------------------------------
// 5. 随机混合回归
// ----------------------------------------------------------------------------
class test_random_regression extends axi_lite_base_test;

  `uvm_component_utils(test_random_regression)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_random_mix::type_id::get());
  endfunction

endclass : test_random_regression


//个人测试场景（2）
// ---- 6. 边界值测试 ----
class test_boundary extends axi_lite_base_test;
  `uvm_component_utils(test_boundary)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_boundary::type_id::get());
  endfunction
endclass : test_boundary


//个人测试场景4
//-增加了一个寄存器-
// ---- 7. LIF_EN 0x0C 寄存器读写定向测试 ----
class test_en_rw extends axi_lite_base_test;
  `uvm_component_utils(test_en_rw)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db #(uvm_object_wrapper)::set(
      this, "env.agent.sqr.main_phase", "default_sequence",
      seq_en_rw::type_id::get());
  endfunction
endclass : test_en_rw


`endif // AXI_LITE_TEST_LIB_SV
