// ============================================================
// UVM 验证平台 - Sequence 库（T1-T5 测试场景）
// 使用标准 start_item/finish_item 机制派发事务
// 场景说明：
//   T1 复位默认值检查：读 0x00 期望 65536、读 0x04 期望 58982
//   T2 正常写读：写 0x00=0x1234 读回；写 0x04=0x5678 读回
//   T3 只读保护：写 0x08=0xABCD 应被忽略，读 0x08 回 spike_count
//   T4 非法地址：写/读 0x100 -> SLVERR
//   T5 背靠背连续多笔读写
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_base_seq extends uvm_sequence #(axi_lite_trans);

  `uvm_object_utils(axi_lite_base_seq)

  function new(string name = "axi_lite_base_seq");
    super.new(name);
  endfunction

  // 发送单笔事务（标准 start_item/finish_item 流控）
  task send_trans(axi_lite_trans::kind_e k, bit [31:0] addr,
                  bit [31:0] data = 32'h0, string desc = "");
    axi_lite_trans tr = axi_lite_trans::type_id::create("tr");
    start_item(tr);
    tr.init(k, addr, data, desc);
    finish_item(tr);
  endtask : send_trans

endclass : axi_lite_base_seq

// ---- 主序列：T1-T5 全部场景 ----
class reg_rw_seq extends axi_lite_base_seq;

  `uvm_object_utils(reg_rw_seq)

  function new(string name = "reg_rw_seq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("SEQ", "==================== TEST START ====================", UVM_LOW)

    // ---- T1：复位默认值（复位释放后读寄存器，scoreboard 比对默认值） ----
    send_trans(axi_lite_trans::READ, 32'h0000_0000, 32'h0, "T1a thresh default");
    send_trans(axi_lite_trans::READ, 32'h0000_0004, 32'h0, "T1b leak default");

    // ---- T2：正常写读 ----
    send_trans(axi_lite_trans::WRITE, 32'h0000_0000, 32'h0000_1234, "T2a write thresh");
    send_trans(axi_lite_trans::READ,  32'h0000_0000, 32'h0, "T2b read thresh");
    send_trans(axi_lite_trans::WRITE, 32'h0000_0004, 32'h0000_5678, "T2c write leak");
    send_trans(axi_lite_trans::READ,  32'h0000_0004, 32'h0, "T2d read leak");

    // ---- T3：只读寄存器保护 ----
    send_trans(axi_lite_trans::WRITE, 32'h0000_0008, 32'h0000_ABCD, "T3a write RO (ignored)");
    send_trans(axi_lite_trans::READ,  32'h0000_0008, 32'h0, "T3b read RO spike_count");

    // ---- T4：非法地址（>=0x0C 必须回 SLVERR） ----
    send_trans(axi_lite_trans::WRITE, 32'h0000_0100, 32'h0000_DEAD, "T4a illegal write");
    send_trans(axi_lite_trans::READ,  32'h0000_0100, 32'h0, "T4b illegal read");

    // ---- T5：背靠背连续多笔读写 ----
    for (int i = 0; i < 4; i++) begin
      send_trans(axi_lite_trans::WRITE, 32'h0000_0000, 32'h1000_0000 + i, "T5 burst write");
      send_trans(axi_lite_trans::READ,  32'h0000_0000, 32'h0, "T5 burst read");
    end

    `uvm_info("SEQ", "==================== TEST END ======================", UVM_LOW)
  endtask : body

endclass : reg_rw_seq
