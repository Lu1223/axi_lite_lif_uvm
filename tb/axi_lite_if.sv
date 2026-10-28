// ============================================================
// UVM 验证平台 - AXI-Lite 总线接口
// ============================================================
interface axi_lite_if(input bit clk);

  logic        rstn = 0;

  // 写地址通道（driver 驱动侧信号初始化 0，防止仿真初期 X 导致 do-while 误判）
  logic [31:0] awaddr = 0;  logic awvalid = 0;  logic awready;
  // 写数据通道
  logic [31:0] wdata  = 0;  logic wvalid  = 0;  logic wready;
  // 写响应通道
  logic [1:0]  bresp;       logic bvalid;       logic bready = 0;
  // 读地址通道
  logic [31:0] araddr = 0;  logic arvalid = 0;  logic arready;
  // 读数据通道
  logic [31:0] rdata;       logic [1:0] rresp;  logic rvalid;  logic rready = 0;

  // LIF 核侧信号（供 monitor/scoreboard 观测）
  logic [31:0] lif_thresh;
  logic [31:0] lif_leak;
  logic [31:0] spike_count = 0;

endinterface : axi_lite_if
