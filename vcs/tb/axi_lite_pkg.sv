// ============================================================================
// axi_lite_pkg.sv —— UVM 验证平台核心 package
// ----------------------------------------------------------------------------
// 教科书式分层结构（自底向上）：
//   axi_lite_transaction   事务级数据包（TLM 层）
//   axi_lite_driver        驱动器：把事务翻译成五通道信号时序（信号层）
//   axi_lite_monitor       监测器：把总线信号采样回事务，送 scoreboard
//   axi_lite_agent         代理：封装 sequencer + driver + monitor
//   axi_lite_scoreboard    计分板：参考模型 + 自动比对
//   axi_lite_coverage      功能覆盖率收集
//   axi_lite_env           环境：组装 agent + scoreboard + coverage
// ============================================================================
package axi_lite_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ==========================================================================
  // 1. axi_lite_transaction —— 事务类
  //    一次 AXI-Lite 读写操作的数据包：地址、数据、方向、观测到的响应
  // ==========================================================================
  class axi_lite_transaction extends uvm_sequence_item;

    typedef enum bit { READ = 0, WRITE = 1 } kind_e;

    rand kind_e       kind;    // 事务方向：读 / 写
    rand bit [31:0]   addr;    // 访问地址（32 位字对齐）
    rand bit [31:0]   data;    // 写数据 / 读回数据
    rand bit [3:0]    strb;    // 字节使能（DUT 未使用，随机化模拟真实主机）
          bit [1:0]   resp;    // 观测到的总线响应：00=OKAY, 10=SLVERR

    // 约束：地址必须 4 字节对齐（AXI-Lite 字访问要求）
    constraint c_addr_align { addr[1:0] == 2'b00; }

    // 约束：数据偶尔落在边界值（0/全F），大部分随机，提高覆盖率
    constraint c_data_border {
      data dist {
        32'h0000_0000 := 1,
        32'hFFFF_FFFF := 1,
        [32'h0000_0001 : 32'hFFFF_FFFE] := 98
      };
    }

    `uvm_object_utils_begin(axi_lite_transaction)
      `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
      `uvm_field_int (addr, UVM_ALL_ON)
      `uvm_field_int (data, UVM_ALL_ON)
      `uvm_field_int (strb, UVM_ALL_ON)
      `uvm_field_int (resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axi_lite_transaction");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("kind=%s addr=0x%08h data=0x%08h strb=%b resp=%0d",
                       kind.name(), addr, data, strb, resp);
    endfunction

  endclass : axi_lite_transaction


  // ==========================================================================
  // 2. axi_lite_driver —— 驱动器（继承 uvm_driver）
  //    从 sequencer 取事务，按 AXI-Lite 协议把事务驱动到五通道上：
  //    写：AW 握手 → W 握手 → 等 B 响应
  //    读：AR 握手 → 等 R 数据
  //    事务之间插入 0~3 拍随机空闲，模拟真实主机行为
  // ==========================================================================
  class axi_lite_driver extends uvm_driver #(axi_lite_transaction);

    virtual axi_lite_if vif;   // 通过 config_db 从 top 层拿到

    `uvm_component_utils(axi_lite_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "No virtual interface found in config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
      vif.wait_rstn_release();          // 等复位释放再开始驱动
      `uvm_info("DRV", "Reset released, driver starts", UVM_MEDIUM)
      forever begin
        axi_lite_transaction tr;
        seq_item_port.get_next_item(tr);
        drive_trans(tr);
        seq_item_port.item_done();
        idle_delay();                   // 事务间随机空闲
      end
    endtask : run_phase

    // ---- 事务分发：按方向走写流程或读流程 ----
    virtual task drive_trans(axi_lite_transaction tr);
      `uvm_info("DRV", $sformatf("Start driving: %s", tr.convert2string()), UVM_HIGH)
      case (tr.kind)
        axi_lite_transaction::WRITE : drive_write(tr);
        axi_lite_transaction::READ  : drive_read (tr);
      endcase
    endtask

    // ---- 写事务：AW → W → B ----
    virtual task drive_write(axi_lite_transaction tr);
      // ---- AW 通道：发地址 ----
      vif.driver_cb.awaddr  <= tr.addr;
      vif.driver_cb.awvalid <= 1'b1;
      @(vif.driver_cb);
      while (!vif.driver_cb.awready) @(vif.driver_cb);
      @(vif.driver_cb);                        // 握手拍之后再撤销
      vif.driver_cb.awvalid <= 1'b0;

      // ---- W 通道：发数据（必须在 AW 握手完成后，满足 SVA a_w_valid_order）----
      vif.driver_cb.wdata  <= tr.data;
      vif.driver_cb.wstrb  <= tr.strb;
      vif.driver_cb.wvalid <= 1'b1;
      @(vif.driver_cb);
      while (!vif.driver_cb.wready) @(vif.driver_cb);
      // 关键：W 握手完成后立即撤销（此时仍处于握手拍的时间步内，
      // VCS 的 clocking block 输出会以 #1step 在本拍生效）。
      // 若再多等一拍，DUT 已在握手拍清掉 w_pending，而 wvalid 还挂着，
      // 会触发 DUT 内部 SVA a_w_valid_order 协议违规。
      vif.driver_cb.wvalid <= 1'b0;

      // ---- B 通道：收响应，记录 resp ----
      while (!vif.driver_cb.bvalid) @(vif.driver_cb);
      tr.resp = vif.driver_cb.bresp;
      vif.driver_cb.bready <= 1'b1;
      @(vif.driver_cb);
      vif.driver_cb.bready <= 1'b0;
      `uvm_info("DRV", $sformatf("Write done, resp=%0d", tr.resp), UVM_HIGH)
    endtask : drive_write

    // ---- 读事务：AR → R ----
    virtual task drive_read(axi_lite_transaction tr);
      // ---- AR 通道：发读地址 ----
      vif.driver_cb.araddr  <= tr.addr;
      vif.driver_cb.arvalid <= 1'b1;
      @(vif.driver_cb);
      while (!vif.driver_cb.arready) @(vif.driver_cb);
      @(vif.driver_cb);
      vif.driver_cb.arvalid <= 1'b0;

      // ---- R 通道：收数据与响应 ----
      while (!vif.driver_cb.rvalid) @(vif.driver_cb);
      tr.data = vif.driver_cb.rdata;
      tr.resp = vif.driver_cb.rresp;
      vif.driver_cb.rready <= 1'b1;
      @(vif.driver_cb);
      vif.driver_cb.rready <= 1'b0;
      `uvm_info("DRV", $sformatf("Read done, resp=%0d", tr.resp), UVM_HIGH)
    endtask : drive_read

    // ---- 随机空闲 0~3 拍 ----
    virtual task idle_delay();
      int unsigned d;
      if (!std::randomize(d) with { d inside {[0:3]}; }) d = 1;
      repeat (d) @(vif.driver_cb);
    endtask

  endclass : axi_lite_driver


  // ==========================================================================
  // 3. axi_lite_monitor —— 监测器（继承 uvm_monitor）
  //    被动采样总线：把五通道上的信号还原成事务，通过 analysis port 广播
  //    写事务在 B 握手完成时送出；读事务在 R 握手完成时送出
  // ==========================================================================
  class axi_lite_monitor extends uvm_monitor;

    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_lite_transaction) ap;//`ap` = **TLM 广播端口**，是 monitor 独有的

    `uvm_component_utils(axi_lite_monitor)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "No virtual interface found in config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
      vif.wait_rstn_release();
      fork
        collect_write();   // 监视写事务（AW/W/B 三个通道）
        collect_read();    // 监视读事务（AR/R 两个通道）
      join
    endtask

    // ---- 写事务监测：AW 锁地址、W 锁数据、B 完成时广播 ----
    virtual task collect_write();
      forever begin
        axi_lite_transaction tr;
        // 等 AW 握手
        @(vif.monitor_cb);
        if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
          tr = axi_lite_transaction::type_id::create("tr");
          tr.kind = axi_lite_transaction::WRITE;
          tr.addr = vif.monitor_cb.awaddr;
          // 等 W 握手（DUT 保证 W 在 AW 之后）
          do @(vif.monitor_cb);
          while (!(vif.monitor_cb.wvalid && vif.monitor_cb.wready));
          tr.data = vif.monitor_cb.wdata;
          tr.strb = vif.monitor_cb.wstrb;
          // 等 B 握手，事务完成
          do @(vif.monitor_cb);
          while (!(vif.monitor_cb.bvalid && vif.monitor_cb.bready));
          tr.resp = vif.monitor_cb.bresp;
          ap.write(tr);//发给 scoreboard；monitor 里有打印。
          `uvm_info("MON", $sformatf("Write observed: %s", tr.convert2string()), UVM_HIGH)
        end
      end
    endtask

    // ---- 读事务监测：AR 锁地址、R 完成时广播 ----
    virtual task collect_read();
      forever begin
        axi_lite_transaction tr;
        @(vif.monitor_cb);
        if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
          tr = axi_lite_transaction::type_id::create("tr");
          tr.kind = axi_lite_transaction::READ;
          tr.addr = vif.monitor_cb.araddr;
          do @(vif.monitor_cb);
          while (!(vif.monitor_cb.rvalid && vif.monitor_cb.rready));
          tr.data = vif.monitor_cb.rdata;
          tr.resp = vif.monitor_cb.rresp;
          ap.write(tr);//发给 scoreboard；monitor 里有打印。
          `uvm_info("MON", $sformatf("Read observed : %s", tr.convert2string()), UVM_HIGH)
        end
      end
    endtask

  endclass : axi_lite_monitor


  // ==========================================================================
  // 4. axi_lite_agent —— 代理（继承 uvm_agent）
  //    把 sequencer / driver / monitor 封装成一个整体
  //    本平台 agent 恒为 active 模式（要主动驱动 DUT）
  // ==========================================================================
  class axi_lite_agent extends uvm_agent;

    axi_lite_driver              drv;
    axi_lite_monitor             mon;
    uvm_sequencer #(axi_lite_transaction) sqr;

    `uvm_component_utils(axi_lite_agent)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axi_lite_monitor::type_id::create("mon", this);
      drv = axi_lite_driver ::type_id::create("drv", this);
      sqr = uvm_sequencer #(axi_lite_transaction)::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(sqr.seq_item_export);  // driver ← sequencer
    endfunction

  endclass : axi_lite_agent


  // ==========================================================================
  // 5. axi_lite_scoreboard —— 计分板（继承 uvm_scoreboard）
  //    内含参考模型：三个寄存器的镜像（thresh / leak / spike_count）
  //    对每笔观测到的事务：
  //      - 写事务：检查响应码；合法地址则更新镜像
  //      - 读事务：用镜像预测读回数据与响应，与实际总线结果比对
  // ==========================================================================
  class axi_lite_scoreboard extends uvm_scoreboard;

    uvm_analysis_imp #(axi_lite_transaction, axi_lite_scoreboard) sb_imp;
    virtual axi_lite_if vif;   // 用于读 spike_count 当前值（TB 驱动为常量，无竞态）

    // ---- 参考模型：寄存器镜像（初值与 DUT 复位默认值一致）----
    localparam logic [31:0] THRESH_DEFAULT = 32'd65536;   // 1.0  (Q16.16)
    localparam logic [31:0] LEAK_DEFAULT   = 32'd58982;   // 0.9  (Q16.16)
    protected logic [31:0] thresh_mirror = THRESH_DEFAULT;
    protected logic [31:0] leak_mirror   = LEAK_DEFAULT;
      protected logic [31:0] en_mirror     = 32'd0;  // ✅ 新增：LIF_EN镜像，复位默认0

    // ---- 统计 ----
    int unsigned num_write_checked = 0;
    int unsigned num_read_checked  = 0;
    int unsigned num_mismatch      = 0;

    `uvm_component_utils(axi_lite_scoreboard)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sb_imp = new("sb_imp", this);
      if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("SCB", "No virtual interface found in config_db")
    endfunction

    // ---- analysis port 入口：monitor 每广播一笔事务，这里比对一笔 ----
    virtual function void write(axi_lite_transaction tr);
      case (tr.kind)
        axi_lite_transaction::WRITE : check_write(tr);
        axi_lite_transaction::READ  : check_read (tr);
      endcase
    endfunction

    // ---- 地址合法性判断（与 DUT 译码逻辑一致）----
    function automatic bit addr_legal(bit [31:0] a);
      return (a[31:4] == 28'd0) && (a[3:2] <= 2'd3);// ✅ 新增 addr_legal() 的 [3:2] <= 2'd2 改成 <= 2'd3
    endfunction

    // ---- 写事务检查 ----
    virtual function void check_write(axi_lite_transaction tr);
      bit [1:0] exp_resp;
      num_write_checked++;
      exp_resp = addr_legal(tr.addr) ? 2'b00 : 2'b10;   // 合法→OKAY，非法→SLVERR

      if (tr.resp !== exp_resp) begin
        num_mismatch++;
        `uvm_error("SCB", $sformatf("[WRITE] resp mismatch: addr=0x%08h got=%0d exp=%0d",
                                    tr.addr, tr.resp, exp_resp))
      end

      // 更新镜像：只读寄存器 0x08 写无效；非法地址不更新
      if (addr_legal(tr.addr)) begin
        case (tr.addr[3:2])
          2'd0 : thresh_mirror = tr.data;   // 0x00 LIF_THRESH
          2'd1 : leak_mirror   = tr.data;   // 0x04 LIF_LEAK
          2'd3 : en_mirror     = tr.data;   // ✅ 新增：0x0C LIF_EN写，更新镜像
          default : ;                        // 0x08 只读，写被忽略
        endcase
      end
    endfunction

    // ---- 读事务检查 ----
    virtual function void check_read(axi_lite_transaction tr);
      bit [1:0]   exp_resp;
      bit [31:0]  exp_data;
      num_read_checked++;

      // 响应码：合法→OKAY，非法→SLVERR
      exp_resp = addr_legal(tr.addr) ? 2'b00 : 2'b10;

      // 返回数据：DUT 的数据选择只取决于 araddr[3:2]（与地址合法性无关）——
      // 例如非法地址 0x100（[3:2]=0）仍会返回 thresh 寄存器值，只是响应码为 SLVERR。
      // 参考模型必须与 DUT 行为完全一致，否则会误报。

      case (tr.addr[3:2])                             // [3:2] 两位已全枚举 0~3，无 default
        2'd0 : exp_data = thresh_mirror;            // [3:2]=0 → 阈值寄存器
        2'd1 : exp_data = leak_mirror;              // [3:2]=1 → 泄漏寄存器
        2'd2 : exp_data = vif.spike_count;          // [3:2]=2 → 脉冲计数（只读直连）
        2'd3 : exp_data = en_mirror;                // [3:2]=3 → 0x0C LIF_EN（场景4新增）
      endcase

      if (tr.resp !== exp_resp) begin
        num_mismatch++;
        `uvm_error("SCB", $sformatf("[READ ] resp mismatch: addr=0x%08h got=%0d exp=%0d",
                                    tr.addr, tr.resp, exp_resp))
      end
      if (tr.data !== exp_data) begin
        num_mismatch++;
        `uvm_error("SCB", $sformatf("[READ ] data mismatch: addr=0x%08h got=0x%08h exp=0x%08h",
                                    tr.addr, tr.data, exp_data))
      end
    endfunction

    // ---- 仿真结束时的汇总报告 ----
    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SCB", $sformatf("Write checked: %0d | Read checked: %0d | Mismatches: %0d",
                                 num_write_checked, num_read_checked, num_mismatch), UVM_NONE)
    endfunction

  endclass : axi_lite_scoreboard


  // ==========================================================================
  // 6. axi_lite_coverage —— 功能覆盖率收集器（继承 uvm_subscriber）
  //    统计：事务方向、地址分布（三个寄存器 + 非法区）、响应码、边界数据
  // ==========================================================================
  class axi_lite_coverage extends uvm_subscriber #(axi_lite_transaction);

    virtual axi_lite_if vif;
    `uvm_component_utils(axi_lite_coverage)

    // covergroup 采样用的当前事务句柄（write() 里先赋值再 sample）
    axi_lite_transaction tr_cov;

    covergroup cg_trans;
      option.per_instance = 1;
      cp_kind  : coverpoint tr_cov.kind {
        bins read  = {axi_lite_transaction::READ };
        bins write = {axi_lite_transaction::WRITE};
      }
      // 地址合法性：合法（4 个寄存器之一）vs 非法（SLVERR 区）
      // 场景4：0x0C 合法化，[3:2] <= 2'd2 改成 <= 2'd3，与 DUT addr_ok 保持一致
      cp_legal : coverpoint (tr_cov.addr[31:4] == 28'd0 && tr_cov.addr[3:2] <= 2'd3) {
        bins legal   = {1};
        bins illegal = {0};
      }
      // 寄存器分布：0x00/0x04/0x08/0x0C 四个寄存器
      cp_reg   : coverpoint tr_cov.addr[3:2] {
        bins thresh = {2'd0};
        bins leak   = {2'd1};
        bins spike  = {2'd2};
        bins en     = {2'd3};   // 0x0C LIF_EN（场景4新增）
      }
      cp_resp  : coverpoint tr_cov.resp {
        bins okay   = {2'b00};
        bins slverr = {2'b10};
      }
      cp_data0 : coverpoint tr_cov.data {
        bins zero  = {32'h0};
        bins ones  = {32'hFFFF_FFFF};
        bins other = {[32'h1 : 32'hFFFF_FFFE]};
      }
      cross_kind_resp : cross cp_kind, cp_resp;     // 读/写 × 响应码组合
    endgroup : cg_trans

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_trans = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual axi_lite_if)::get(this, "", "vif", vif))
        `uvm_fatal("COV", "No virtual interface found in config_db")
    endfunction

    // uvm_subscriber 的入口：每笔事务采样一次覆盖率
    virtual function void write(axi_lite_transaction t);
      tr_cov = t;
      cg_trans.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("COV", $sformatf("Coverage: %.1f%%",
                                 cg_trans.get_inst_coverage()), UVM_NONE)
    endfunction

  endclass : axi_lite_coverage


  // ==========================================================================
  // 7. axi_lite_env —— 环境（继承 uvm_env）
  //    组装 agent + scoreboard + coverage，并完成 TLM 连接
  // ==========================================================================
  class axi_lite_env extends uvm_env;

    axi_lite_agent      agent;
    axi_lite_scoreboard scb;
    axi_lite_coverage   cov;

    `uvm_component_utils(axi_lite_env)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = axi_lite_agent     ::type_id::create("agent", this);
      scb   = axi_lite_scoreboard::type_id::create("scb"  , this);
      cov   = axi_lite_coverage  ::type_id::create("cov"  , this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // monitor 广播的事务 → scoreboard 比对 + coverage 采样（一对多广播）
      agent.mon.ap.connect(scb.sb_imp);
      agent.mon.ap.connect(cov.analysis_export);
    endfunction

  endclass : axi_lite_env

  // ==========================================================================
  // 以 `include 方式把 sequence 库和测试库并入 package
  // （它们共享 package 作用域，可直接引用 axi_lite_transaction 等类型）
  // ==========================================================================
  `include "axi_lite_seq_lib.sv"
  `include "axi_lite_test_lib.sv"

endpackage : axi_lite_pkg
