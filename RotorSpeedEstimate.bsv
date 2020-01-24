import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

//
import Standardize::*;
import SgolayFilt::*;
import CumTrapz::*;
import ButterFilt::*;
import Estimate::*;
import Diff::*;
import RDivideScalar::*;
//
import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

typedef 4 ZeroLen;

typedef enum {INIT, STANDARDIZE1, SGOLAYFILT, CUMTRAPZ, BUTTERFILT, STANDARDIZE2, ESTIMATE, DIFF, RDIVIDE1, RDIVIDE2, MEDFILT1} State deriving(Bits,Eq);

interface RotorSpeedEstimateIfc;
//INIT
	method Action loadSgolay(Bit#(64) weight);
	method Action loadAxis(Bit#(64) inc);
	method Action setTotal(Bit#(20) bitTot, Bit#(64) dblTot);
	method Action put(Bit#(64) data);
	method Action start;
endinterface

function BRAMRequest#(Bit#(20), Bit#(64)) makeRequest(Bool write, Bit#(20) addr, Bit#(64) data);
	return BRAMRequest{
		write: write,
		responseOnWrite:False,
		address: addr,
		datain: data};
endfunction

module mkRotorSpeedEstimate(RotorSpeedEstimateIfc);

	BRAM_Configure bram_cfg = defaultValue;
	BRAM2Port#(Bit#(20), Bit#(64)) data_in <- mkBRAM2Server(bram_cfg);
	
	StandardizeIfc standardize <- mkStandardize;
	SgolayFiltIfc sgolayFilt <- mkSgolayFilt;
	CumTrapzIfc cumTrapz <- mkCumTrapz;
	ButterFiltIfc butterFilt <- mkButterFilt;
	EstimateIfc estimate <- mkEstimate;
	DiffIfc diff <- mkDiff;
	RDivideScalarIfc rdividescalar <- mkRDivideScalar;
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	FIFOF#(Bit#(64)) inputQ <- mkSizedFIFOF(200000);
	
	Reg#(State) rseState <- mkReg(INIT);
	Reg#(Bit#(20)) count <- mkReg(0);
	
	Reg#(Bool) writeFlag <- mkReg(False);
	
	Reg#(Bit#(20)) bitTotal <- mkReg(200000);
	Reg#(Bit#(64)) dblTotal <- mkReg('b0100000100001000011010100000000000000000000000000000000000000000);
	
	rule stdRelay1(rseState == STANDARDIZE1 && count < bitTotal);
        inputQ.deq;
        Bit#(64) val = inputQ.first;
		standardize.put(val);
		count <= count + 1;
	endrule
	
	rule startStandardize1(rseState == STANDARDIZE1 && count == bitTotal);
		count <= 0;
		standardize.start;
	endrule
	
	rule endStandardize1(rseState == STANDARDIZE1 && standardize.hasStd());
		//rseState <= CUMTRAPZ;
		rseState <= SGOLAYFILT;
		count <= 0;
	endrule
	
	rule sgolayRelay(rseState == SGOLAYFILT && count < bitTotal);
		Bit#(64) val <- standardize.get();
		sgolayFilt.put(val);
		count <= count + 1;
	endrule
		
	rule startSgolay(rseState == SGOLAYFILT && count == bitTotal);
		count <= 0;
		sgolayFilt.start;
	endrule
	
	rule endSgolay(rseState == SGOLAYFILT && sgolayFilt.hasSgolay());
		rseState <= CUMTRAPZ;
	endrule
	
	rule cumTrapzRelay(rseState == CUMTRAPZ && count < bitTotal);
		Bit#(64) val <- sgolayFilt.get();
		//Bit#(64) val <- standardize.get();
		
		count <= count + 1;
		cumTrapz.put(val);
	endrule
	
	rule startCumTrapz(rseState == CUMTRAPZ && count == bitTotal);
		count <= 0;
		cumTrapz.start;
	endrule
	
	rule endCumTrapz(rseState == CUMTRAPZ && cumTrapz.hasCum());
		rseState <= BUTTERFILT;
		//rseState <= STANDARDIZE2;
		standardize.clear;
		$display("switch to std2");
	endrule
	
	rule butterRelay(rseState == BUTTERFILT && count < bitTotal);
		Bit#(64) val <- cumTrapz.get();
		count <= count + 1;
		butterFilt.put(val);
	endrule
	
	rule startButter(rseState == BUTTERFILT && count == bitTotal);
		count <= 0;
		butterFilt.start;
	endrule
	
	rule endButter(rseState == BUTTERFILT && butterFilt.hasButter());
		rseState <= STANDARDIZE2;
		standardize.clear;
	endrule
	
	rule stdRelay2(rseState == STANDARDIZE2 && count < bitTotal);
		
		Bit#(64) val <- butterFilt.get;
		//Bit#(64) val <- cumTrapz.get;
		//$display("relay std %u %b", count,val);
		if (count < 4) begin
			standardize.put(0);
		end else begin
			standardize.put(val);
		end
		count <= count + 1;
	endrule
	
	rule startStandardize2(rseState == STANDARDIZE2 && count == bitTotal);
		count <= 0;
		standardize.start;
	endrule
	
	rule endStandardize2(rseState == STANDARDIZE2 && standardize.hasStd());
		rseState <= ESTIMATE;
		count <= 0;
	endrule
	
	rule estRelay(rseState == ESTIMATE && count < bitTotal);
		Bit#(64) val <- standardize.get;
		estimate.put(val);
		count <= count + 1;
	endrule
	
	rule startEstimate(rseState == ESTIMATE && count == bitTotal);
		count <= 0;
		estimate.start;
	endrule
	
	rule endEstimate(rseState == ESTIMATE && estimate.hasEst());
		rseState <= DIFF;
		count <= 0;
	endrule
	
	rule diffRelay(rseState == DIFF && count < bitTotal);
		Bit#(64) val <- estimate.get;
		diff.put(val);
		count <= count + 1;
	endrule
	
	rule startDiff(rseState == DIFF && count == bitTotal);
		count <= 0;
		estimate.start;
	endrule
	
	rule endDiff(rseState == DIFF && diff.hasDiff());
		rseState <= RDIVIDE1;
		count <= 0;
	endrule 
	
	rule rdivRelay1(rseState == RDIVIDE1 && count < bitTotal-1);
		Bit#(64) val <- diff.get;
		rdividescalar.put(val);
		count <= count + 1;
	endrule
	
	rule startRDiv1(rseState == RDIVIDE1 && count == bitTotal -1);
		rseState <= RDIVIDE1;
		count <= 0;
		rdividescalar.setScalar('b0011111111110000000000000000000000000000000000000000000000000000, True);
		rdividescalar.start;
	endrule
	
	rule endRDiv1(rseState == RDIVIDE1 && diff.hasDiff());
		rseState <= RDIVIDE2;
		count <= 0;
	endrule 
	
	rule rdivRelay2(rseState == RDIVIDE2 && count < bitTotal-1);
		Bit#(64) val <- diff.get;
		rdividescalar.put(val);
		count <= count + 1;
	endrule
	
	rule startRDiv2(rseState == RDIVIDE2 && count == bitTotal -1);
		rseState <= RDIVIDE1;
		count <= 0;
		rdividescalar.setScalar('b0100000000000000000000000000000000000000000000000000000000000000, False);
		rdividescalar.start;
	endrule
	
	rule endRDiv2(rseState == RDIVIDE2 && rdividescalar.hasRDiv());
		rseState <= RDIVIDE2;
		count <= 0;
	endrule
	
	method Action put(Bit#(64) data);
		inputQ.enq(data);
	endmethod
	
	method Action loadSgolay(Bit#(64) weight);
		sgolayFilt.loadSgolay(weight);
	endmethod
	
	method Action loadAxis(Bit#(64) inc);
		estimate.loadAxis(inc);
	endmethod
	
	method Action start;
		$display( "Starting RotorSpeedEstimate. \n");
		rseState <= STANDARDIZE1;
	endmethod
	
	method Action setTotal(Bit#(20) bitTot, Bit#(64) dblTot);
		bitTotal <= bitTot;
		dblTotal <= dblTot;
		standardize.setTotal(bitTot, dblTot);
	endmethod

endmodule: mkRotorSpeedEstimate