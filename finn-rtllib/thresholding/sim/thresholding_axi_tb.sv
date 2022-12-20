/******************************************************************************
 * Copyright (C) 2022, Advanced Micro Devices, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 *  3. Neither the name of the copyright holder nor the names of its
 *     contributors may be used to endorse or promote products derived from
 *     this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION). HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * @brief	Testbench for thresholding_axi.
 * @author	Monica Chiosa <monica.chiosa@amd.com>
 * @author	Thomas Preußer <thomas.preusser@amd.com>
 */

module thresholding_axi_tb #(
	int unsigned  N  = 4,	// output precision
	int unsigned  C  = 6,	// number of channels
	int unsigned  PE = 3,
	real  M0 = 4.2,	// slope of the uniform thresholding line
	real  B0 = 6.8	// offset of the uniform thresholding line
);

	//-----------------------------------------------------------------------
	// For each channel = [0,channel):
	//     M_channel = M0 + CX*channel
	//     B_channel = B0 + CX*channel
	// Input/threshold precision computed according with the maximum posible value
	localparam real  CX = 2.375;
	localparam int unsigned  K = 1 + $clog2((2**N-1)*(M0+C*CX) + (B0+C*CX)); // sign + magnitude
	localparam int unsigned  C_BITS = C < 2? 1 : $clog2(C);

	localparam int unsigned  ROUNDS = 1623;

	typedef int threshs_t[C][2**N-1];
	function threshs_t init_thresholds();
		automatic threshs_t  res;
		for(int unsigned  c = 0; c < C; c++) begin
			automatic real  m = M0 + c*CX;
			automatic real  b = B0 + c*CX;
			foreach(res[c][i]) begin
				res[c][i] = int'($ceil(m*i + b));
			end
		end
		return  res;
	endfunction : init_thresholds
	localparam threshs_t  THRESHS = init_thresholds();

	//-----------------------------------------------------------------------
	// Global Control
	logic  clk = 0;
	always #5ns clk = !clk;

	logic  rst = 1;
	initial begin
		repeat(16) @(posedge clk);
		rst <= 0;
	end

	//-----------------------------------------------------------------------
	// DUT interface signals
	typedef logic [$clog2(C/PE)+$clog2(PE)+N+1:0]  waddr_t;
	struct {
		logic    vld;
		logic    rdy;
		waddr_t  val;
	} waddr;

	typedef logic [31:0]  wdata_t;
	struct {
		logic    vld;
		logic    rdy;
		wdata_t  val;
	} wdata;

	typedef logic [PE-1:0][K-1:0]  idata_t;
	struct {
		logic    vld;
		logic    rdy;
		idata_t  val;
	} idata;

	typedef logic [PE-1:0][N-1:0]  odata_t;
	struct {
		logic    vld;
		logic    rdy;
		odata_t  val;
	} odata;

	// DUT
	thresholding_axi #(.N(N), .K(K), .C(C), .PE(PE))
	dut (
		.ap_clk(clk), .ap_rst_n(!rst),

		// AXI LITE
		// Writing
		.s_axilite_AWVALID(waddr.vld), .s_axilite_AWREADY(waddr.rdy), .s_axilite_AWADDR (waddr.val),
		.s_axilite_WVALID (wdata.vld), .s_axilite_WREADY (wdata.rdy), .s_axilite_WDATA (wdata.val), .s_axilite_WSTRB ('x),
		.s_axilite_BVALID(), .s_axilite_BREADY('1), .s_axilite_BRESP (),

		// Reading - not used
		.s_axilite_ARVALID('0), .s_axilite_ARREADY(), .s_axilite_ARADDR('x),
		.s_axilite_RVALID(), .s_axilite_RREADY('0), .s_axilite_RDATA(), .s_axilite_RRESP(),

		// AXI Stream
		// Input
		.s_axis_tvalid(idata.vld),
		.s_axis_tready(idata.rdy),
		.s_axis_tdata (idata.val),

		// Output
		.m_axis_tvalid(odata.vld),
		.m_axis_tready(odata.rdy),
		.m_axis_tdata (odata.val)
	);

	//- Stimuli -------------------------------------------------------------
	idata_t  Q[$];
	initial begin
		waddr.vld =  0;
		waddr.val = 'x;
		wdata.vld =  0;
		wdata.val = 'x;
		idata.vld =  0;
		idata.val = 'x;
		odata.rdy =  0;

		// Report testbench details
		$display("Tresholding: K=%0d -> N=%0d", K, N);
		for(int unsigned  c = 0; c < C; c++) begin
			$write("Channel #%0d: Thresholds = {", c);
			for(int unsigned  i = 0; i < 2**N-1; i++)  $write(" %0d", THRESHS[c][i]);
			$display(" }");
		end

		@(posedge clk iff !rst);

		// Load up Thresholds
		waddr.vld <= 1;
		wdata.vld <= 1;
		for(int unsigned  c = 0; c < C; c++) begin
			for(int unsigned  i = 0; i < 2**N-1; i++) begin
				waddr.val[0+:N+2] <= { i[N-1:0], 2'b00 };
				if(C > 1) begin
					if(PE > 1)  waddr.val[N+2+:$clog2(PE)] <= c % PE;
					waddr.val[N+2+$clog2(PE)+:$clog2(C)] <= c / PE;
				end
				wdata.val <= THRESHS[c][i];
				@(posedge clk iff waddr.rdy || wdata.rdy);
				assert(waddr.rdy && wdata.rdy) else begin
					$error("Unsupported unsynced address and data acknowledgement.");
					$stop;
				end
			end
		end
		waddr.vld <=  0;
		wdata.vld <=  0;
		waddr.val <= 'x;
		wdata.val <= 'x;

		// AXI4Stream MST Writes input values
		repeat(ROUNDS) begin
			automatic idata_t  val;
			foreach(val[pe])  val[pe] = $urandom();

			repeat(2-$clog2(1+$urandom()%4)) @(posedge clk);
			idata.vld <= 1;
			idata.val <= val;
			@(posedge clk iff idata.rdy);
			idata.vld <=  0;
			idata.val <= 'x;

			Q.push_back(val);
		end

		repeat(N+12)  @(posedge clk);
		assert(Q.size() == 0) else begin
			$error("Missing %0d outputs.", Q.size());
			$stop;
		end

		$display("Test completed with %0d tests.", ROUNDS);
		$display("===============================");
		$finish;
	end

	// Output Checker -------------------------------------------------------
	int unsigned  cnl_read = 0;
	always_ff @(posedge clk) begin
		if(rst) begin
			odata.rdy <= 0;
			cnl_read   = 0;
		end
		else begin
			if(!odata.rdy || odata.vld)  odata.rdy <= ($urandom()%3 != 0);
			if(odata.rdy && odata.vld) begin
				assert(Q.size()) begin
					automatic idata_t  x = Q.pop_front();
					automatic odata_t  y = odata.val;

					for(int unsigned  pe = 0; pe < PE; pe++) begin
						assert(
							((y[pe] ==      0) || ($signed(THRESHS[cnl_read][y[pe]-1]) <= $signed(x[pe]))) &&
							((y[pe] == 2**N-1) || ($signed(x[pe]) < $signed(THRESHS[cnl_read][y[pe]])))
						) else begin
	//						automatic string  l = 0 < y? $sformatf("[%0d] %0d", y-1, $signed(THRESHS[cnl_read][y-1])) : "-INFTY";
	//						automatic string  r = y < 2**N-1? $sformatf("[%0d] %0d", y, $signed(THRESHS[cnl_read][y])) : "INFTY";
	//						$error("Channel #%0d: Mispositioned output violating: %s <= [%0d] %0d < %s", cnl_read, l, y, x, r);
							$error("Channel #%0d on PE #%0d: %0d -> %0d", cnl_read, pe, $signed(x[pe]), $signed(y[pe]));
							$stop;
						end

						cnl_read = (cnl_read+1) % C;
					end
				end
				else begin
					$error("Spurious output.");
					$stop;
				end
			end
		end
	end

endmodule: thresholding_axi_tb
