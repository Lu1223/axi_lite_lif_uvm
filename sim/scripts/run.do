# ============================================================
# 批量仿真脚本：显式记录波形 + 运行 + 退出
# 只记录 testbench 顶层的 vif（interface 信号）和 dut 内部信号，
# 不记录 UVM 类内部（那样波形会巨大且没用）
# ============================================================
log /uvm_test_top/clk
log -r /uvm_test_top/vif/*
log -r /uvm_test_top/dut/*
run -all
quit -f
