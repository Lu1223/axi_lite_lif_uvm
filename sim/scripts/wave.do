# ============================================================
# 波形窗口配置：时钟/复位 + AXI-Lite 五通道 + LIF 信号
# 数据/地址总线用十六进制显示，控制信号保持二进制
# ============================================================
add wave -position end sim:/uvm_test_top/clk
add wave -position end sim:/uvm_test_top/vif/rstn
add wave -position end -group "AW channel" \
  -radix hex sim:/uvm_test_top/vif/awaddr \
  sim:/uvm_test_top/vif/awvalid sim:/uvm_test_top/vif/awready
add wave -position end -group "W channel" \
  -radix hex sim:/uvm_test_top/vif/wdata \
  sim:/uvm_test_top/vif/wvalid sim:/uvm_test_top/vif/wready
add wave -position end -group "B channel" \
  sim:/uvm_test_top/vif/bresp sim:/uvm_test_top/vif/bvalid sim:/uvm_test_top/vif/bready
add wave -position end -group "AR channel" \
  -radix hex sim:/uvm_test_top/vif/araddr \
  sim:/uvm_test_top/vif/arvalid sim:/uvm_test_top/vif/arready
add wave -position end -group "R channel" \
  -radix hex sim:/uvm_test_top/vif/rdata \
  sim:/uvm_test_top/vif/rresp sim:/uvm_test_top/vif/rvalid sim:/uvm_test_top/vif/rready
add wave -position end -group "LIF signals" \
  -radix hex sim:/uvm_test_top/vif/lif_thresh sim:/uvm_test_top/vif/lif_leak sim:/uvm_test_top/vif/spike_count
run -all
