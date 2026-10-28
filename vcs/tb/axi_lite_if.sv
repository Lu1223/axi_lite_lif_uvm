// ============================================================================
// axi_lite_if.sv —— AXI-Lite 总线接口（interface + clocking block + modport）
// ----------------------------------------------------------------------------
// 作用：把 DUT 的 5 通道信号打包进一个 interface，UVM 的 driver/monitor
//       都通过 virtual interface 访问总线，这是 UVM 验证平台的标准做法。
// 三个部分：
//   1) 信号声明：AXI-Lite 五通道 + LIF 侧信号（spike_count 由 TB 驱动）
//   2) clocking block：driver_cb（driver 用，输出偏斜）、monitor_cb（monitor 用）
//   3) modport：给 DUT 连接用的方向定义
// ============================================================================
interface axi_lite_if (input logic clk, input logic rstn);

  // ------------------- 写地址通道 AW -------------------
  logic [31:0] awaddr;
  logic        awvalid;
  logic        awready;

  // ------------------- 写数据通道 W -------------------
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;

  // ------------------- 写响应通道 B -------------------
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;

  // ------------------- 读地址通道 AR -------------------
  logic [31:0] araddr;
  logic        arvalid;
  logic        arready;

  // ------------------- 读数据通道 R -------------------
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  // ------------------- LIF 侧信号（TB 驱动 spike_count） -------------------
  logic [31:0] spike_count;

  // ==========================================================================
  // clocking block：定义信号相对时钟的采样/驱动时序
  //   driver_cb ：driver 用它驱动总线（输出偏斜 #1step，避免与 DUT 竞争）
  //   monitor_cb：monitor 用它采样总线（输入偏斜 #1step，采样稳定值）
  // ==========================================================================
  clocking driver_cb @(posedge clk);
    default input #1step output #1step;
    output awaddr, awvalid;
    input  awready;
    output wdata, wstrb, wvalid;
    input  wready;
    input  bresp, bvalid;
    output bready;
    output araddr, arvalid;
    input  arready;
    input  rdata, rresp, rvalid;
    output rready;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step output #1step;
    input awaddr, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking

  // ==========================================================================
  // modport：给 DUT 例化用的方向定义（testbench 侧视角）
  // ==========================================================================
  modport dut_mp (
    input  awaddr, awvalid, output awready,
    input  wdata, wstrb, wvalid, output wready,
    output bresp, bvalid, input  bready,
    input  araddr, arvalid, output arready,
    output rdata, rresp, rvalid, input  rready,
    input  spike_count
  );

  // ==========================================================================
  // wait_rstn_release：等复位释放（rstn 上升沿）。
  // driver/monitor 在 run_phase 开头调用，保证复位期间不驱动总线
  // ==========================================================================
  task automatic wait_rstn_release();
    @(posedge rstn);
  endtask

endinterface
