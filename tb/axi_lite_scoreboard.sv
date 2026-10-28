// ============================================================
// UVM 验证平台 - Scoreboard（寄存器镜像 + 响应/数据比对）
// 寄存器地图：
//   0x00 LIF_THRESH   RW  默认 65536
//   0x04 LIF_LEAK     RW  默认 58982
//   0x08 SPIKE_COUNT  RO  （LIF 核维护，TB 固定为 DEAD_BEEF）
//   >=0x0C 非法 -> 必须回 SLVERR
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"

class axi_lite_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(axi_lite_scoreboard)

  // 分析端口：接收 monitor 广播
  uvm_analysis_imp #(axi_lite_trans, axi_lite_scoreboard) ap;

  // 寄存器镜像
  bit [31:0] mirror_thresh = 32'd65536;   // 复位默认值
  bit [31:0] mirror_leak   = 32'd58982;
  bit [31:0] exp_spike     = 32'hDEAD_BEEF;

  int pass_cnt = 0;
  int fail_cnt = 0;

  function new(string name = "axi_lite_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  // ---- 打印检查结果 ----
  // 注意：不能叫 check —— 与 uvm_component 内置虚方法 check(uvm_phase) 冲突，会编译报错
  function void do_check(string name, bit ok);
    if (ok) begin
      $display("[PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("[FAIL] %s", name);
      fail_cnt++;
    end
  endfunction : do_check

  // ---- 主比对逻辑：接收 monitor 观察到的事务 ----
  function void write(axi_lite_trans tr);
    case (tr.addr)
      32'h0000_0000 : begin  // 阈值 RW
        if (tr.kind == axi_lite_trans::WRITE) begin
          do_check($sformatf("write thresh resp OKAY (resp=%0d)", tr.resp), tr.resp == 2'b00);
          mirror_thresh = tr.data;
        end else begin
          do_check($sformatf("read thresh == written (0x%08h)", tr.data), tr.data == mirror_thresh);
        end
      end
      32'h0000_0004 : begin  // 泄漏 RW
        if (tr.kind == axi_lite_trans::WRITE) begin
          do_check($sformatf("write leak resp OKAY (resp=%0d)", tr.resp), tr.resp == 2'b00);
          mirror_leak = tr.data;
        end else begin
          do_check($sformatf("read leak == written (0x%08h)", tr.data), tr.data == mirror_leak);
        end
      end
      32'h0000_0008 : begin  // 脉冲计数 RO
        if (tr.kind == axi_lite_trans::WRITE) begin
          do_check("write RO resp OKAY (ignored)", tr.resp == 2'b00);
        end else begin
          do_check($sformatf("RO reads spike_count (0x%08h)", tr.data), tr.data == exp_spike);
        end
      end
      default : begin        // 非法地址：必须回 SLVERR
        if (tr.kind == axi_lite_trans::WRITE)
          do_check($sformatf("illegal write @0x%08h returns SLVERR (resp=%0d)", tr.addr, tr.resp), tr.resp == 2'b10);
        else
          do_check($sformatf("illegal read  @0x%08h returns SLVERR (resp=%0d)", tr.addr, tr.resp), tr.resp == 2'b10);
      end
    endcase
  endfunction : write

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    $display("==================== TEST SUMMARY ====================");
    $display(" RESULT: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display(" ALL TESTS PASSED !");
    else               $display(" SOME TESTS FAILED !!!");
    $display("=====================================================");
  endfunction : report_phase

endclass : axi_lite_scoreboard
