// ---------------------------------------------------------------------
// Self-checking testbench for the RV32I core
//  - writes a commit log (every register write and every store)
//  - if expected_commit_log.txt is present, compares every commit
//    against it and stops at the first mismatch
//  - stops with FAIL as soon as the PC goes X
//  - PASS when the program stores DONE_DATA at DONE_ADDR
//  - FAIL on timeout
// ---------------------------------------------------------------------

module test_bench;

  // ---------------- Test configuration ----------------
  // test_all.mem        : DONE_ADDR = 60, DONE_DATA = 32'h7637112C
  // max-in-array program: DONE_ADDR = 24, DONE_DATA = 42
  // Fibonacci program   : DONE_ADDR = 36, DONE_DATA = 34
  localparam logic [31:0] DONE_ADDR  = 32'd60;
  localparam logic [31:0] DONE_DATA  = 32'h7637112C;
  localparam int          MAX_CYCLES = 2000;

  // ---------------- Clock and reset ----------------
  logic clk     = 1'b0;
  logic reset_n = 1'b0;
  int   cycle   = 0;
  int   log_fd, exp_fd;
  int   n_commits = 0;
  logic done    = 1'b0;                  // set when the final store is seen

  always #5 clk = ~clk;

  top #(.RESET_PC(32'h0)) dut (
    .clk     (clk),
    .reset_n (reset_n)
  );

  initial begin
    $dumpfile("test_bench.vcd");
    $dumpvars(0, test_bench);
    log_fd = $fopen("commit_log.txt", "w");
    exp_fd = $fopen("expected_commit_log.txt", "r");   // 0 if the file is absent
    if (exp_fd == 0)
      $display("NOTE: expected_commit_log.txt not found - writing the log without comparing");

    repeat (2) @(posedge clk);           // hold reset for 2 cycles
    @(negedge clk);                      // release away from the rising edge (no race)
    reset_n = 1'b1;
  end

  // ---------------- Write one commit, and compare it ----------------
  task automatic commit(input string line);
    string           expected;
    reg [8*80-1:0]   buffer;              // $fgets target (a reg works in every simulator)
    int              n;
    n_commits++;
    $fdisplay(log_fd, "%s", line);
    if (exp_fd != 0) begin
      buffer   = '0;
      n        = $fgets(buffer, exp_fd);
      expected = $sformatf("%0s", buffer);
      // strip line feed (10) and the carriage return (13) of Windows files
      while (expected.len() > 0 &&
             (expected[expected.len()-1] == 8'd10 || expected[expected.len()-1] == 8'd13))
        expected = expected.substr(0, expected.len()-2);
      if (line != expected) begin
        $display("FAIL: commit #%0d mismatch at cycle %0d, pc = %h, instr = %h",
                 n_commits, cycle, dut.pc, dut.instruction);
        $display("      got      : %s", line);
        if (n == 0) expected = "<end of reference>";
        $display("      expected : %s", expected);
        $fclose(log_fd);
        $stop;
      end
    end
  endtask

  // ---------------- Checker ----------------
  // Sample on the falling edge: all combinational logic has settled,
  // and these are the writes that commit on the next rising edge.
  always @(negedge clk) begin
    if (reset_n) begin
      cycle <= cycle + 1;

      // 0) Final store was seen last cycle and is now in memory -> stop
      if (done) begin
        $fclose(log_fd);
        $stop;
      end

      // 1) PC must never be X/Z
      if ($isunknown(dut.pc)) begin
        $display("FAIL: PC is X at cycle %0d (last instr = %h)", cycle, dut.instruction);
        $stop;
      end

      // 2) Register writes
      if (dut.rf_wr_en && dut.rd_addr != 5'd0) begin
        $display("[%4d] pc=%h instr=%h  x%0d <= %h", cycle, dut.pc, dut.instruction, dut.rd_addr, dut.wr_data);
        commit($sformatf("x%0d %h", dut.rd_addr, dut.wr_data));
      end

      // 3) Stores, and the pass/fail check
      if (dut.dmem_req && dut.dmem_wr_en) begin
        $display("[%4d] pc=%h instr=%h  MEM[%0d] <= %h", cycle, dut.pc, dut.instruction, dut.dmem_addr, dut.dmem_wr_data);
        commit($sformatf("M[%h] %h", dut.dmem_addr, dut.dmem_wr_data));

        if (dut.dmem_addr == DONE_ADDR) begin
          if (dut.dmem_wr_data == DONE_DATA) begin
            $display("PASS: MEM[%0d] = %h after %0d cycles, %0d commits", DONE_ADDR, DONE_DATA, cycle, n_commits);
            if (exp_fd != 0) $display("      commit log matches expected_commit_log.txt line for line");
          end else
            $display("FAIL: MEM[%0d] = %h, expected %h", DONE_ADDR, dut.dmem_wr_data, DONE_DATA);
          done <= 1'b1;   // stop one cycle later, after the store lands in memory
        end
      end

      // 4) Timeout
      if (cycle >= MAX_CYCLES) begin
        $display("FAIL: timeout after %0d cycles (pc = %h)", MAX_CYCLES, dut.pc);
        $fclose(log_fd);
        $stop;
      end
    end
  end

endmodule
