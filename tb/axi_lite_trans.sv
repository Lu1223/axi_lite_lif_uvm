// ============================================================
// UVM 验证平台 - AXI-Lite 事务（transaction）
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_trans extends uvm_sequence_item;

  typedef enum bit { WRITE, READ } kind_e;

  rand kind_e      kind;      // 事务类型
  rand bit  [31:0] addr;      // 地址
  rand bit  [31:0] data;      // 写数据 / 读回数据
  rand bit  [1:0]  resp;      // 响应：00=OKAY 10=SLVERR

  string           desc;      // 测试项描述（用于打印 PASS/FAIL）

  `uvm_object_utils_begin(axi_lite_trans)
    `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)
    `uvm_field_int(resp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi_lite_trans");
    super.new(name);
  endfunction

  // 便捷构造函数：定向场景直接赋值（不依赖随机化）
  function void init(kind_e k, bit [31:0] a, bit [31:0] d, string s = "");
    kind = k; addr = a; data = d; resp = 2'b00; desc = s;
  endfunction

endclass : axi_lite_trans
