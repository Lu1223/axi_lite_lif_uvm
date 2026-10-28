// ============================================================================
// 新模块2：axi_lite_lif_reg_slave.sv —— AXI-Lite 从机（LIF 寄存器配置）
// ----------------------------------------------------------------------------
// 功能：为 LIF 神经元核提供寄存器配置接口（阈值/泄漏/脉冲计数），
//       是整个 SNN-FPGA 项目里"PS 配置 PL"的标准接口模块。
// 寄存器地图（4 字节对齐）：
//   0x00 LIF_THRESH  可读写  阈值（Q16.16 定点，默认 65536 = 1.0）
//   0x04 LIF_LEAK    可读写  泄漏系数（Q16.16，默认 58982 = 0.9）
//   0x08 SPIKE_COUNT 只读    脉冲计数（由 LIF 核累加，PS 只读）
// 非法地址（>= 0x0C）：回 SLVERR（从设备错误响应）
// 内嵌 SVA 断言：
//   a_aw_timeout / a_w_timeout / a_ar_timeout：握手超时监控
//   a_w_valid_order：AXI-Lite 要求写数据 W 不能早于地址 AW 握手
//   a_illegal_addr_resp：非法地址必须回 SLVERR（功能自检）
//   a_bvalid_stable：BVALID 置位后 BREADY 响应前必须保持
// ============================================================================
module axi_lite_lif_reg_slave (
  input  logic        clk,
  input  logic        rstn,
  // ---- 写地址通道 AW ----
  input  logic [31:0] s_axi_awaddr,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // ---- 写数据通道 W ----
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // ---- 写响应通道 B ----
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // ---- 读地址通道 AR ----
  input  logic [31:0] s_axi_araddr,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // ---- 读数据通道 R ----
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,
  // ---- LIF 寄存器（连到 LIF 神经元核） ----
  output logic [31:0] lif_thresh,     // 阈值寄存器
  output logic [31:0] lif_leak,       // 泄漏系数寄存器
  input  logic [31:0] spike_count     // 脉冲计数（LIF 核维护）
);

  // ==================== 寄存器 ====================
  localparam [31:0] THRESH_DEFAULT = 32'd65536;   // 1.0 << 16
  localparam [31:0] LEAK_DEFAULT   = 32'd58982;   // 0.9 * 65536

  logic [31:0] thresh_reg, leak_reg;
  logic [31:0] awaddr_l, araddr_l;
  logic        w_pending;      // AW 已握手、等 W
  logic        illegal_addr;   // 地址越界标志

  assign lif_thresh = thresh_reg;
  assign lif_leak   = leak_reg;

  // 地址译码（组合）：合法地址 = 0x00/0x04/0x08（三个寄存器的字偏移），
  // 即 [31:4] 全 0 且 [3:2] <= 2；0x0C 及以上非法
  wire addr_ok_w = (awaddr_l[31:4] == 28'd0) && (awaddr_l[3:2] <= 2'd2);
  wire addr_ok_r = (araddr_l[31:4] == 28'd0) && (araddr_l[3:2] <= 2'd2);

  // ==================== 写通道状态机（AW -> W -> B） ====================
  always_ff @(posedge clk) begin
    if (!rstn) begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      s_axi_bresp   <= 2'b00;
      awaddr_l      <= 32'd0;
      w_pending     <= 1'b0;
      illegal_addr  <= 1'b0;
      thresh_reg    <= THRESH_DEFAULT;
      leak_reg      <= LEAK_DEFAULT;
    end else begin
      // ---- AW 握手 ----
      if (s_axi_awvalid && s_axi_awready) begin
        awaddr_l      <= s_axi_awaddr;
        w_pending     <= 1'b1;
        s_axi_awready <= 1'b0;
        $display("  [DUT] AW handshake at %0t addr=%08h", $time, s_axi_awaddr);
      end else if (!w_pending && !s_axi_bvalid) begin
        s_axi_awready <= 1'b1;   // 空闲时随时可收地址
      end

      // ---- W 握手 + 寄存器写入 ----
      if (w_pending && s_axi_wvalid && s_axi_wready) begin
        w_pending    <= 1'b0;
        illegal_addr <= ~addr_ok_w;
        if (addr_ok_w) begin
          case (awaddr_l[3:2])
            2'd0: thresh_reg <= s_axi_wdata;   // 0x00 阈值
            2'd1: leak_reg   <= s_axi_wdata;   // 0x04 泄漏
            default: ;                          // 0x08 只读，写忽略
          endcase
        end
        s_axi_bvalid <= 1'b1;
        s_axi_bresp  <= addr_ok_w ? 2'b00 : 2'b10;   // OKAY / SLVERR
      end else if (w_pending) begin
        s_axi_wready <= 1'b1;
      end

      // ---- B 握手 ----
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid  <= 1'b0;
        illegal_addr  <= 1'b0;
        s_axi_awready <= 1'b1;
        s_axi_wready  <= 1'b0;
      end
    end
  end

  // ==================== 读通道状态机（AR -> R） ====================
  logic r_pending;
  always_ff @(posedge clk) begin
    if (!rstn) begin
      s_axi_arready <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= 32'd0;
      s_axi_rresp   <= 2'b00;
      araddr_l      <= 32'd0;
      r_pending     <= 1'b0;
    end else begin
      // ---- AR 握手 ----
      if (s_axi_arvalid && s_axi_arready) begin
        araddr_l      <= s_axi_araddr;
        r_pending     <= 1'b1;
        s_axi_arready <= 1'b0;
      end else if (!r_pending && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;
      end

      // ---- R 响应（寄存器读，1 拍后给出数据） ----
      if (r_pending && !s_axi_rvalid) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rresp  <= addr_ok_r ? 2'b00 : 2'b10;
        case (araddr_l[3:2])
          2'd0: s_axi_rdata <= thresh_reg;    // 0x00
          2'd1: s_axi_rdata <= leak_reg;      // 0x04
          2'd2: s_axi_rdata <= spike_count;   // 0x08 只读
          default: s_axi_rdata <= 32'd0;
        endcase
      end

      // ---- R 握手 ----
      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid  <= 1'b0;
        r_pending     <= 1'b0;
        s_axi_arready <= 1'b1;
      end
    end
  end

  // ==================== SVA 断言（协议监控） ====================
  // 默认不编译（ModelSim ASE 不仿真断言；EDA Playground 免费版 license 也不支持）。
  // 换用 Questa/VCS 等支持断言的模拟器时，加 +define+USE_SVA 启用。
  `ifdef USE_SVA
  // 1) 握手超时：VALID 拉高后 16 拍内 READY 必须响应，否则说明主机/从机卡死
  property p_handshake_timeout(valid, ready);
    @(posedge clk) disable iff (!rstn)
    valid |-> ##[1:16] ready;
  endproperty
  a_aw_timeout: assert property (p_handshake_timeout(s_axi_awvalid, s_axi_awready))
    else $error("[SVA] AW handshake timeout: AWVALID high but AWREADY no response in 16 cycles");
  a_w_timeout:  assert property (p_handshake_timeout(s_axi_wvalid,  s_axi_wready))
    else $error("[SVA] W handshake timeout");
  a_ar_timeout: assert property (p_handshake_timeout(s_axi_arvalid, s_axi_arready))
    else $error("[SVA] AR handshake timeout");
  a_b_timeout:  assert property (p_handshake_timeout(s_axi_bvalid,  s_axi_bready))
    else $error("[SVA] B handshake timeout");
  a_r_timeout:  assert property (p_handshake_timeout(s_axi_rvalid,  s_axi_rready))
    else $error("[SVA] R handshake timeout");

  // 2) 协议顺序：AXI-Lite 要求 WVALID 不能早于 AW 握手（AW 必须先到）
  property p_w_after_aw;
    @(posedge clk) disable iff (!rstn)
    s_axi_wvalid |-> $past(s_axi_awvalid && s_axi_awready) || w_pending;
  endproperty
  a_w_valid_order: assert property (p_w_after_aw)
    else $error("[SVA] Protocol order violation: WVALID before AW handshake");

  // 3) 非法地址访问：检测到非法地址（>=0x0C）的写/读，必须回 SLVERR
  a_illegal_addr_resp: assert property (
    @(posedge clk) disable iff (!rstn)
    illegal_addr |-> s_axi_bresp == 2'b10)
    else $error("[SVA] Illegal address access did not return SLVERR");

  // 4) 稳定性：BVALID/RVALID 置位后在对方响应前必须保持（不许撤销）
  a_bvalid_stable: assert property (
    @(posedge clk) disable iff (!rstn)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid)
    else $error("[SVA] BVALID dropped before BREADY");
  a_rvalid_stable: assert property (
    @(posedge clk) disable iff (!rstn)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid)
    else $error("[SVA] RVALID dropped before RREADY");

  // 5) 功能自检：默认值检查（复位释放后寄存器应为默认值）
  a_thresh_default: assert property (
    @(posedge clk) disable iff (!rstn)
    $rose(rstn) |-> ##1 thresh_reg == THRESH_DEFAULT)
    else $error("[SVA] LIF_THRESH default value wrong");
  `endif

endmodule
