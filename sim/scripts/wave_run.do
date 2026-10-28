# ============================================================
# GUI 波形仿真脚本：打开即重新仿真（1160ns 只需几秒），实时显示波形
# 先显式 log 信号，再添加到波形窗口，最后 run
# ============================================================
log /uvm_test_top/clk
log -r /uvm_test_top/vif/*
log -r /uvm_test_top/dut/*
add wave -position end /uvm_test_top/clk
add wave -position end /uvm_test_top/vif/rstn
add wave -position end -group "AW channel" \
  -radix hex /uvm_test_top/vif/awaddr \
  /uvm_test_top/vif/awvalid /uvm_test_top/vif/awready
add wave -position end -group "W channel" \
  -radix hex /uvm_test_top/vif/wdata \
  /uvm_test_top/vif/wvalid /uvm_test_top/vif/wready
add wave -position end -group "B channel" \
  /uvm_test_top/vif/bresp /uvm_test_top/vif/bvalid /uvm_test_top/vif/bready
add wave -position end -group "AR channel" \
  -radix hex /uvm_test_top/vif/araddr \
  /uvm_test_top/vif/arvalid /uvm_test_top/vif/arready
add wave -position end -group "R channel" \
  -radix hex /uvm_test_top/vif/rdata \
  /uvm_test_top/vif/rresp /uvm_test_top/vif/rvalid /uvm_test_top/vif/rready
add wave -position end -group "LIF signals" \
  -radix hex /uvm_test_top/vif/lif_thresh /uvm_test_top/vif/lif_leak /uvm_test_top/vif/spike_count
add wave -position end -group "DUT internal" \
  -radix hex /uvm_test_top/dut/thresh_reg /uvm_test_top/dut/leak_reg \
  /uvm_test_top/dut/w_pending /uvm_test_top/dut/r_pending /uvm_test_top/dut/illegal_addr
run -all
wave zoomfull
