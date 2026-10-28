// ============================================================================
// axi_lite_seq_lib.sv —— sequence 库（激励序列）
// ----------------------------------------------------------------------------
// sequence 是 UVM 的激励生成层：不直接碰信号，只产生事务交给 sequencer，
// sequencer 再派发给 driver。不同测试 = 换不同 sequence，平台复用。
//
// 本文件定义：
//   axi_lite_base_seq     基类：产生 num_trans 笔随机事务
//   seq_reset_default     复位后读 3 个寄存器，验证默认值（靠 scoreboard 比对）
//   seq_reg_rw            阈值/泄漏寄存器 写→读回
//   seq_ro_protect        对只读寄存器 0x08 写数据，验证写无效
//   seq_illegal_addr      读写非法地址，验证 SLVERR
//   seq_random_mix        随机读写混合回归
// ============================================================================
`ifndef AXI_LITE_SEQ_LIB_SV
`define AXI_LITE_SEQ_LIB_SV

// ---- 基类：随机事务流 ----
class axi_lite_base_seq extends uvm_sequence #(axi_lite_transaction);

  int unsigned num_trans = 10;      // 默认产生 10 笔
  rand bit [31:0]  wr_data;         // 供派生类使用的随机数据池

  `uvm_object_utils(axi_lite_base_seq)

  function new(string name = "axi_lite_base_seq");
    super.new(name);
  endfunction

  // ---- objection 机制：sequence 执行期间拉住 run phase ----
  // UVM 的 run phase 只有当所有 objection 都 drop 后才结束。
  // 如果 sequence 不 raise objection，run phase 会在 0 时刻直接结束，
  // driver 还没来得及驱动任何事务仿真就 $finish 了。
  //
  // 注意：必须用 get_starting_phase() 而不是 starting_phase 变量！
  // VCS 自带 UVM-1.2 中 starting_phase 是废弃写法（UVM_DEPRECATED），
  // 库内部把真正的值存在 m_starting_phase_dap 里，
  // 直接读 starting_phase 会得到 NULL。
  virtual task pre_body();
    uvm_phase ph = get_starting_phase();
    if (ph != null)
      ph.raise_objection(this, "sequence running");
  endtask

  virtual task post_body();
    uvm_phase ph = get_starting_phase();
    if (ph != null)
      ph.drop_objection(this, "sequence done");
  endtask

  virtual task body();
    repeat (num_trans) begin
      `uvm_do(req)
    end
  endtask

endclass : axi_lite_base_seq


// ---- 1. 复位默认值检查：复位后直接读三个寄存器 ----
// scoreboard 的参考模型初始值 = DUT 复位默认值，读回自动比对
class seq_reset_default extends axi_lite_base_seq;

  `uvm_object_utils(seq_reset_default)

  function new(string name = "seq_reset_default");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", "Checking reset default values of 3 registers", UVM_MEDIUM)
    `uvm_do_with(req, { kind == axi_lite_transaction::READ; addr == 32'h0000_0000; })  // THRESH = 65536
    `uvm_do_with(req, { kind == axi_lite_transaction::READ; addr == 32'h0000_0004; })  // LEAK   = 58982
    `uvm_do_with(req, { kind == axi_lite_transaction::READ; addr == 32'h0000_0008; })  // SPIKE_COUNT
  endtask

endclass : seq_reset_default


// ---- 2. 寄存器读写：写随机值 → 读回（scoreboard 自动比对） ----
class seq_reg_rw extends axi_lite_base_seq;

  `uvm_object_utils(seq_reg_rw)

  function new(string name = "seq_reg_rw");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", "RW test: write random values then read back", UVM_MEDIUM)
    // ---- 阈值寄存器 0x00：写 3 次不同值，每次读回 ----
    repeat (3) begin
      `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0000; })
      `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0000; })
    end
    // ---- 泄漏寄存器 0x04：写 3 次不同值，每次读回 ----
    repeat (3) begin
      `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0004; })
      `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0004; })
    end
  endtask

endclass : seq_reg_rw


// ---- 3. 只读寄存器保护：写 0x08 应被忽略，读回仍是 spike_count ----
class seq_ro_protect extends axi_lite_base_seq;

  `uvm_object_utils(seq_ro_protect)

  function new(string name = "seq_ro_protect");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", "RO protect test: write to 0x08 must be ignored", UVM_MEDIUM)
    // 写只读寄存器：DUT 忽略数据，但地址合法 → 响应 OKAY
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE;
                        addr == 32'h0000_0008;
                        data == 32'hDEAD_BEEF; })//DEAD_BEEF（修改过，测试场景1）
    // 读回：应仍是 TB 驱动的 spike_count 值（scoreboard 用 vif.spike_count 预测）
    `uvm_do_with(req, { kind == axi_lite_transaction::READ; addr == 32'h0000_0008; })
  endtask

endclass : seq_ro_protect


// ---- 4. 非法地址访问：读写 >=0x0C 的地址，必须返回 SLVERR ----
class seq_illegal_addr extends axi_lite_base_seq;

  `uvm_object_utils(seq_illegal_addr)

  function new(string name = "seq_illegal_addr");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("SEQ", "Illegal addr test: expect SLVERR for addr >= 0x10", UVM_MEDIUM)
    // 场景4：0x0C 已合法化（LIF_EN），故非法地址从 0x100 / 0xFFFF_FFFC 起测
    // 0x100：高 28 位非 0，越界
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0100; })
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0100; })
    // 0xFFFF_FFFC：最高地址，越界
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'hFFFF_FFFC; })
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'hFFFF_FFFC; })
  endtask

endclass : seq_illegal_addr


// ---- 5. 随机混合回归：大量随机读写（合法为主 + 少量非法） ----
// 配合 coverage 收集，把 cp_legal/cp_reg/cp_resp/cp_data 全部打满
class seq_random_mix extends axi_lite_base_seq;

  `uvm_object_utils(seq_random_mix)

  function new(string name = "seq_random_mix");
    super.new(name);
    num_trans = 500;//个人测试场景3——从 200改为500
  endfunction

  virtual task body();
    int unsigned i;
    `uvm_info("SEQ", "Random regression: 500 mixed transactions", UVM_MEDIUM)
    for (i = 0; i < num_trans; i++) begin
      if ((i % 20) == 19) begin      // 每 20 笔插 1 笔非法（5%）
        // 非法地址轮换：0x0C 已合法（场景4），只剩 0x100 / 0xFFFF_FFFC
        // 注意：非法笔的步长是 20（i = 19,39,59...），
        // 轮换索引必须用 (i/20)%2 —— 若用 (i/10)%2，i/10 恒为偶数，
        // 永远只走 0x100 分支，0xFFFF_FFFC 一次都覆盖不到！
        case ((i / 20) % 2)
          0 : `uvm_do_with(req, { addr == 32'h0000_0100; })
          1 : `uvm_do_with(req, { addr == 32'hFFFF_FFFC; })
        endcase
      end else begin
        // 95% 的普通事务：随机方向 + 四个合法寄存器地址
        `uvm_do_with(req, { addr[31:4] == 28'd0;
                            addr[3:2] inside {[0:3]}; })  // 含 0x0C LIF_EN（场景4）
      end
    end
  endtask

endclass : seq_random_mix




//测试场景（个人练习题2）
// ---- 6. 边界值定向测试：全 0 / 全 F ----
class seq_boundary extends axi_lite_base_seq;
  `uvm_object_utils(seq_boundary)
  function new(string name = "seq_boundary");
    super.new(name);
  endfunction
  virtual task body();
    `uvm_info("SEQ", "Boundary test: 0 and all-ones", UVM_MEDIUM)
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0000; data == 32'h0000_0000; })
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0000; })
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0000; data == 32'hFFFF_FFFF; })
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0000; })
  endtask
endclass : seq_boundary


//测试场景4
//新增一个寄存器（0x0C LIF_EN，读写）
class seq_en_rw extends axi_lite_base_seq;
  `uvm_object_utils(seq_en_rw)
  function new(string name = "seq_en_rw"); super.new(name); endfunction
  virtual task body();
    `uvm_info("SEQ", "EN register RW test: 0x0C LIF_EN", UVM_MEDIUM)
    // ① 先给 0x00/0x04 写已知值——防"路由错误"盲区：
    //    若 DUT 把 0x0C 的写错存进 thresh/leak，后面第③步读回会露馅
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0000; data == 32'hAAAA_0000; })
    `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_0004; data == 32'hBBBB_0000; })
    // ② 对 0x0C（LIF_EN）写随机值→读回，3 轮（scoreboard 用 en_mirror 自动比对）
    repeat (3) begin
      `uvm_do_with(req, { kind == axi_lite_transaction::WRITE; addr == 32'h0000_000C; })
      `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_000C; })
    end
    // ③ 读回 0x00/0x04，确认没被 0x0C 的写串扰（独立性检查）
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0000; })
    `uvm_do_with(req, { kind == axi_lite_transaction::READ ; addr == 32'h0000_0004; })
  endtask
endclass : seq_en_rw






`endif // AXI_LITE_SEQ_LIB_SV


