// ============================================================================
// 新模块2：axi_lite_lif_reg_slave.sv —— AXI-Lite 从机（LIF 寄存器配置）
// ----------------------------------------------------------------------------
// 功能：为 LIF 神经元核提供寄存器配置接口（阈值/泄漏/脉冲计数），
//       是整个 SNN-FPGA 项目里"PS 配置 PL"的标准接口模块。
// 寄存器地图（4 字节对齐，AXI-Lite访问按字寻址，地址最低2bit为0）：
//   0x00 LIF_THRESH   可读写  阈值（Q16.16 定点，默认 65536 = 1.0）
//   0x04 LIF_LEAK    可读写  泄漏系数（Q16.16，默认 58982 = 0.9）
//   0x08 SPIKE_COUNT 只读    脉冲计数（由 LIF 核维护，本模块只读取，不能写）
// 非法地址（>= 0x0C）：总线返回 SLVERR（从设备错误响应）
// 内嵌 SVA 断言：自动监控AXI协议，仿真时抓握手、时序、地址错误
//   a_aw_timeout / a_w_timeout / a_ar_timeout：握手超时监控
//   a_w_valid_order：AXI-Lite 协议要求：写数据W不能早于地址AW握手完成
//   a_illegal_addr_resp：非法地址访问，必须返回SLVERR错误码（功能自检）
//   a_bvalid_stable：BVALID应答信号，在BREADY到来前不能拉低
// ============================================================================
module axi_lite_lif_reg_slave (
  input  logic         clk,                // 全局时钟
  input  logic         rstn,               // 低电平复位
  // ---- 写地址通道 AW（AXI-Lite写地址通道） ----
  input  logic [31:0]  s_axi_awaddr,       // 主机发来写地址
  input  logic         s_axi_awvalid,      // 主机：AW地址有效标志
  output logic         s_axi_awready,      // 从机：从机准备好接收AW地址
  // ---- 写数据通道 W（AXI-Lite写数据通道） ----
  input  logic [31:0]  s_axi_wdata,         // 主机发来写数据
  input  logic [3:0]   s_axi_wstrb,         // 字节使能（本模块暂未使用，保留标准AXI端口）
  input  logic         s_axi_wvalid,        // 主机：W数据有效标志
  output logic         s_axi_wready,        // 从机：从机准备好接收W写数据
  // ---- 写响应通道 B（写操作完成应答） ----
  output logic [1:0]   s_axi_bresp,         // 写返回状态：00=OK,10=SLVERR
  output logic         s_axi_bvalid,        // 从机：B应答有效
  input  logic         s_axi_bready,        // 主机：主机准备接收B应答
  // ---- 读地址通道 AR（AXI-Lite读地址通道） ----
  input  logic [31:0]  s_axi_araddr,        // 主机发来读地址
  input  logic         s_axi_arvalid,       // 主机：AR读地址有效
  output logic         s_axi_arready,      // 从机：从机准备接收AR地址
  // ---- 读数据通道 R（读操作返回数据+状态） ----
  output logic [31:0]  s_axi_rdata,         // 返回给主机的读数据
  output logic [1:0]   s_axi_rresp,         // 读返回状态：00=OK,10=SLVERR
  output logic         s_axi_rvalid,        // 从机：R数据有效
  input  logic         s_axi_rready,         // 主机：主机准备接收R数据
  // ---- LIF 寄存器信号（对接PL端LIF神经元核） ----
  output logic [31:0]  lif_thresh,          // 输出：LIF发放阈值，送给LIF核
  output logic [31:0]  lif_leak,            // 输出：LIF膜电位泄漏系数，送给LIF核
  input  logic [31:0]  spike_count,          // 输入：LIF核统计的脉冲个数，本模块只读

//个人场景测试4
// 端口区加：
output logic [31:0] lif_en      // 使能寄存器（新增）


);
  // ==================== 参数与内部寄存器定义 ====================
  // Q16.16定点数：高16bit整数，低16bit小数。1.0 = 1<<16 = 65536
  localparam [31:0] THRESH_DEFAULT = 32'd65536;   // LIF阈值默认值 1.0
  localparam [31:0] LEAK_DEFAULT   = 32'd58982;   // 泄漏系数默认0.9 ≈ 0.9*65536
  logic [31:0] thresh_reg;  // LIF阈值寄存器，PS可读写
  logic [31:0] leak_reg;   // LIF泄漏系数寄存器，PS可读写

  logic [31:0] awaddr_l;   // 锁存：保存AW通道握手成功后的写地址
  logic [31:0] araddr_l;   // 锁存：保存AR通道握手成功后的读地址

  logic        w_pending;    // 写通道状态标记：AW握手完成，等待接收W写数据
  logic        illegal_addr; // 标记本次访问地址是否非法（越界）

  // 组合逻辑：寄存器输出直接连到LIF神经元模块
  assign lif_thresh = thresh_reg;//thresh_reg属于 模块内部寄存器**，不是端口。
  assign lif_leak   = leak_reg;

  //个人场景测试4
  // 寄存器区加：
logic [31:0] en_reg;
assign lif_en = en_reg;



  // --------------------地址译码组合逻辑--------------------
  // // 合法地址范围：0x00 / 0x04 / 0x08
  // // [31:4]==0：高28位为0，只访问低16M地址；[3:2]<=2：字偏移0,1,2（对应0x00,0x04,0x08）
  // wire addr_ok_w = (awaddr_l[31:4] == 28'd0) && (awaddr_l[3:2] <= 2'd2); //写地址合法标志
  // wire addr_ok_r = (araddr_l[31:4] == 28'd0) && (araddr_l[3:2] <= 2'd2); //读地址合法标志


// 修改前，个人测试场景4
// wire addr_ok_w = (awaddr_l[31:4] == 28'd0) && (awaddr_l[3:2] <= 2'd2);
// wire addr_ok_r = (araddr_l[31:4] == 28'd0) && (araddr_l[3:2] <= 2'd2);

// ✅ 修改后
wire addr_ok_w = (awaddr_l[31:4] == 28'd0) && (awaddr_l[3:2] <= 2'd3);
wire addr_ok_r = (araddr_l[31:4] == 28'd0) && (araddr_l[3:2] <= 2'd3);




  // ==================== 写通道状态机（AXI-Lite标准顺序 AW -> W -> B） ====================
  // 写流程：主机发AW地址→从机握手锁地址 →主机发W数据→从机握手锁数据 →从机返回B应答
  always_ff @(posedge clk) begin
    if (!rstn) begin
      //复位：所有AXI输出拉低，寄存器加载默认值
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      s_axi_bresp   <= 2'b00;
      awaddr_l      <= 32'd0;
      w_pending     <= 1'b0;
      illegal_addr  <= 1'b0;
      thresh_reg    <= THRESH_DEFAULT;
      leak_reg      <= LEAK_DEFAULT;

      en_reg        <= 32'd0; // ✅ 新增：en_reg复位默认0




    end else begin
      // ---- AW地址通道握手逻辑 ----
      // AWVALID & AWREADY 同时为高：握手成功，锁存写地址
      if (s_axi_awvalid && s_axi_awready) begin
        awaddr_l      <= s_axi_awaddr; //锁存主机发送的写地址
        w_pending     <= 1'b1;         //标记：AW握手完成，等待W数据
        s_axi_awready <= 1'b0;         //关闭AW接收，等待W通道
        $display("  [DUT] AW handshake at %0t addr=%08h", $time, s_axi_awaddr);
      end else if (!w_pending && !s_axi_bvalid) begin
        s_axi_awready <= 1'b1;   //空闲状态：打开AW通道，随时接收主机地址
      end

      // ---- W数据通道握手 + 寄存器写入逻辑 ----
      // w_pending=1代表AW已经握手，此时等待WVALID和WREADY握手
      if (w_pending && s_axi_wvalid && s_axi_wready) begin
        w_pending    <= 1'b0;               //W握手完成，清除等待标记
        illegal_addr <= ~addr_ok_w;         //判断地址是否非法

        if (addr_ok_w) begin //地址合法，执行寄存器写操作
          case (awaddr_l[3:2]) //按字偏移选择寄存器
            2'd0: thresh_reg <= s_axi_wdata;   //0x00 LIF_THRESH，写入阈值
            2'd1: leak_reg   <= s_axi_wdata;   //0x04 LIF_LEAK，写入泄漏系数


          2'd3: en_reg     <= s_axi_wdata;   //✅ 新增：0x0C LIF_EN



            default: ;                         //0x08 SPIKE_COUNT只读，写操作直接忽略
          endcase
        end

        s_axi_bvalid <= 1'b1;                            //拉高应答有效，准备返回B通道
        s_axi_bresp  <= addr_ok_w ? 2'b00 : 2'b10;       //地址正常返回OK，非法返回SLVERR
      end else if (w_pending) begin
        s_axi_wready <= 1'b1; //AW握手完成，持续打开W通道，等待主机发W数据
      end

      // ---- B写应答通道握手逻辑 ----
      // BVALID & BREADY同时高：主机收到应答，本次写事务全部结束
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid  <= 1'b0;   //清除应答有效标志
        illegal_addr  <= 1'b0;
        s_axi_awready <= 1'b1;   //重新回到空闲，准备接收下一次AW地址
        s_axi_wready  <= 1'b0;
      end
    end
  end

  // ==================== 读通道状态机（AR -> R） ====================
  // 读流程：主机发AR读地址→从机握手锁地址 →从机输出R数据+状态，主机握手接收
  logic r_pending; //读通道标记：AR握手完成，等待生成R返回数据
  always_ff @(posedge clk) begin
    if (!rstn) begin
      s_axi_arready <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= 32'd0;
      s_axi_rresp   <= 2'b00;
      araddr_l      <= 32'd0;
      r_pending     <= 1'b0;
    end else begin
      // ---- AR读地址握手 ----
      if (s_axi_arvalid && s_axi_arready) begin
        araddr_l      <= s_axi_araddr; //锁存读地址
        r_pending     <= 1'b1;        //标记AR握手完成，准备生成读数据
        s_axi_arready <= 1'b0;        //关闭AR接收
      end else if (!r_pending && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;        //空闲状态，打开AR接收
      end

      // ---- R读数据生成 ----
      if (r_pending && !s_axi_rvalid) begin
        s_axi_rvalid <= 1'b1;
        s_axi_rresp  <= addr_ok_r ? 2'b00 : 2'b10; //合法OK，非法SLVERR
        case (araddr_l[3:2])                    // [3:2] 两位已全枚举 0~3，无 default
          2'd0: s_axi_rdata <= thresh_reg;    //0x00：读阈值寄存器
          2'd1: s_axi_rdata <= leak_reg;      //0x04：读泄漏系数寄存器
          2'd2: s_axi_rdata <= spike_count;   //0x08：读LIF输入脉冲计数（只读）
          2'd3: s_axi_rdata <= en_reg;        //0x0C：读使能寄存器（场景4新增）
        endcase
      end

      // ---- R通道握手完成 ----
      if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid  <= 1'b0;
        r_pending     <= 1'b0;
        s_axi_arready <= 1'b1; //回到空闲，等待下一次读地址
      end
    end
  end

  // ==================== SVA 断言（协议监控，仅仿真生效，综合会自动忽略） ====================
  // SVA 作用：仿真中自动检查AXI协议是否违反，出现问题直接打印$error，快速定位bug
  // 1) 握手超时属性：valid拉高后，0~16拍内必须收到ready，否则判定卡死
  //    注意必须用 ##[0:16] 而不是 ##[1:16]：AXI 协议允许 ready 与 valid
  //    在同一拍完成握手。若用 ##[1:16]，握手当拍 valid 拉低后，
  //    断言仍要求未来 1~16 拍内 ready 再次出现——对"握手当拍完成、
  //    ready 随即撤销"的正常从机行为会误报超时（UVM 回归时曾出现 40 次误报）。
  property p_handshake_timeout(valid, ready);
    @(posedge clk) disable iff (!rstn)  //复位期间不检查
    valid |-> ##[0:16] ready;           //valid成立，则当拍起16拍内ready必须出现
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

  // 2) 协议顺序规则：WVALID不能早于AW握手完成（AXI-Lite协议要求）
  property p_w_after_aw;
    @(posedge clk) disable iff (!rstn)
    s_axi_wvalid |-> $past(s_axi_awvalid && s_axi_awready) || w_pending;
  endproperty
  a_w_valid_order: assert property (p_w_after_aw)
    else $error("[SVA] Protocol order violation: WVALID before AW handshake");

  // 3) 非法地址写访问，必须返回SLVERR（2'b10）
  a_illegal_addr_resp: assert property (
    @(posedge clk) disable iff (!rstn)
    illegal_addr |-> s_axi_bresp == 2'b10)
    else $error("[SVA] Illegal address access did not return SLVERR");

  // 4) 信号稳定性：BVALID拉高后，主机BREADY没有来之前，BVALID不能掉
  a_bvalid_stable: assert property (
    @(posedge clk) disable iff (!rstn)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid)
    else $error("[SVA] BVALID dropped before BREADY");
  a_rvalid_stable: assert property (
    @(posedge clk) disable iff (!rstn)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid)
    else $error("[SVA] RVALID dropped before RREADY");

  // 5) 复位释放后，阈值寄存器必须等于默认值
  a_thresh_default: assert property (
    @(posedge clk) disable iff (!rstn)
    $rose(rstn) |-> ##1 thresh_reg == THRESH_DEFAULT)
    else $error("[SVA] LIF_THRESH default value wrong");

endmodule
// ============================================================================
// 本模块实现功能：AXI-Lite 从机接口 + LIF 配置寄存器 + SVA 协议断言
// 项目位置：阶段一基础模块，后续 LIF 核 / HLS IP 的配置口都复用此设计
// ============================================================================
