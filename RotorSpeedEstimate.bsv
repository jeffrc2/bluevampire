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
import MedFilt1::*;
//
import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

typedef 4 ZeroLen;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, STANDARDIZE1, SGOLAYFILT, CUMTRAPZ, BUTTERFILT, STANDARDIZE2, ESTIMATE, DIFF, RDIVIDE1, RDIVIDE2, MEDFILT1} State deriving(Bits,Eq);

interface RotorSpeedEstimateIfc#(numeric type datalen);
//INIT
	method Action loadSgolay(Bit#(64) weight);
	method Action loadAxis(Bit#(64) inc);
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasRSE;
	method Bit#(CountLen#(datalen)) getNewTotal;
	method ActionValue#(Bit#(64)) getTime;
	method ActionValue#(Bit#(64)) getSpeed;
endinterface

module mkRotorSpeedEstimate(RotorSpeedEstimateIfc#(datalen));

	BRAM_Configure bram_cfg = defaultValue;
	//BRAM2Port#(Bit#(CountLen#(datalen)), Bit#(64)) data_in <- mkBRAM2Server(bram_cfg);
	
	StandardizeIfc#(datalen) standardize <- mkStandardize;
	SgolayFiltIfc#(datalen) sgolayFilt <- mkSgolayFilt;
	CumTrapzIfc#(datalen) cumTrapz <- mkCumTrapz;
	ButterFiltIfc#(datalen) butterFilt <- mkButterFilt;
	EstimateIfc#(datalen) estimate <- mkEstimate;
	DiffIfc#(datalen) diff <- mkDiff;
	RDivideScalarIfc#(datalen) rdividescalar <- mkRDivideScalar;
	MedFilt1Ifc#(datalen) medFilt1 <- mkMedFilt1;
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	FIFOF#(Bit#(64)) inputQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) timeQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	Reg#(Bool) running <- mkReg(False);
	
	Reg#(State) rseState <- mkReg(INIT);
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	Reg#(Bool) rseDone <- mkReg(False);
	
	//Reg#(Bit#(CountLen#(datalen))) bitTotal <- mkReg(fromInteger(valueOf(datalen)));
	Reg#(Bit#(64)) dblTotal <- mkReg('b0100000100001000011010100000000000000000000000000000000000000000);
	
	rule stdRelay1(rseState == STANDARDIZE1 && count < fromInteger(valueOf(datalen)));
        inputQ.deq;
        Bit#(64) val = inputQ.first;
		standardize.put(val);
		count <= count + 1;
	endrule
	
	rule startStandardize1(rseState == STANDARDIZE1 && count == fromInteger(valueOf(datalen)) && !running);
		count <= 0;
		standardize.start;
		running <= True;
	endrule
	
	rule endStandardize1(rseState == STANDARDIZE1 && standardize.hasStd());
		rseState <= SGOLAYFILT;
		running <= False;
`ifdef BSIM
		$display("Relaying to SgolayFilt.\n");
`endif
	endrule
	
	rule sgolayRelay(rseState == SGOLAYFILT && count < fromInteger(valueOf(datalen))  && !running);
		Bit#(64) val <- standardize.get();
		sgolayFilt.put(val);
		count <= count + 1;
	endrule
		
	rule startSgolay(rseState == SGOLAYFILT && count == fromInteger(valueOf(datalen)));
		count <= 0;
		sgolayFilt.start;
		running <= True;
	endrule
	
	rule endSgolay(rseState == SGOLAYFILT && sgolayFilt.hasSgolay());
		rseState <= CUMTRAPZ;
		running <= False;
`ifdef BSIM
		$display("Relaying to CumTrapz.\n");
`endif
	endrule
	
	rule cumTrapzRelay(rseState == CUMTRAPZ && count < fromInteger(valueOf(datalen))  && !running);
		Bit#(64) val <- sgolayFilt.get();
		
		count <= count + 1;
		cumTrapz.put(val);
	endrule
	
	rule startCumTrapz(rseState == CUMTRAPZ && count == fromInteger(valueOf(datalen)));
		count <= 0;
		cumTrapz.start;
		running <= True;
	endrule
	
	rule endCumTrapz(rseState == CUMTRAPZ && cumTrapz.hasCum());
		rseState <= BUTTERFILT;
		running <= False;
		//rseState <= STANDARDIZE2;
		standardize.clear;
`ifdef BSIM
		$display("Relaying to ButterFilt.\n");
`endif
	endrule
	
	rule butterRelay(rseState == BUTTERFILT && count < fromInteger(valueOf(datalen))  && !running);
		Bit#(64) val <- cumTrapz.get();
		count <= count + 1;
		butterFilt.put(val);
	endrule
	
	rule startButter(rseState == BUTTERFILT && count == fromInteger(valueOf(datalen)));
		count <= 0;
		butterFilt.start;
		running <= True;
	endrule
	
	rule endButter(rseState == BUTTERFILT && butterFilt.hasButter());
		rseState <= STANDARDIZE2;
		running <= False;
		standardize.clear;
`ifdef BSIM
		$display("Relaying to Standardize2.\n");
`endif
	endrule
	
	rule stdRelay2(rseState == STANDARDIZE2 && count < fromInteger(valueOf(datalen))  && !running);
		
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
	
	rule startStandardize2(rseState == STANDARDIZE2 && count == fromInteger(valueOf(datalen)));
		count <= 0;
		standardize.start;
		running <= True;
	endrule
	
	rule endStandardize2(rseState == STANDARDIZE2 && standardize.hasStd());
		rseState <= ESTIMATE;
		running <= False;
		count <= 0;
`ifdef BSIM
		$display("Relaying to Estimate.\n");
`endif
	endrule
	
	rule estRelay(rseState == ESTIMATE && count < fromInteger(valueOf(datalen))  && !running);
		Bit#(64) val <- standardize.get;
		estimate.put(val);
		count <= count + 1;
	endrule
	
	rule startEstimate(rseState == ESTIMATE && count == fromInteger(valueOf(datalen)));
		count <= 0;
		estimate.start;
		running <= True;
	endrule
	
	rule endEstimate(rseState == ESTIMATE && estimate.hasEst());
		rseState <= DIFF;
		count <= 0;
		running <= False;
		Bit#(CountLen#(datalen)) newTotal = estimate.getNewTotal;
		diff.setTotal(newTotal);
		rdividescalar.setTotal(newTotal);
`ifdef BSIM
		$display("Relaying to Diff.\n");
`endif
	endrule
	
	rule diffRelay(rseState == DIFF && count < estimate.getNewTotal && !running);
		Bit#(64) val <- estimate.get;
		diff.put(val);
		count <= count + 1;
	endrule
	
	rule startDiff(rseState == DIFF && count == estimate.getNewTotal);
		count <= 0;
		estimate.start;
		running <= True;
	endrule
	
	rule endDiff(rseState == DIFF && diff.hasDiff());
		rseState <= RDIVIDE1;
		count <= 0;
		running <= False;
`ifdef BSIM
		$display("Relaying to RDivide1.\n");
`endif
	endrule 
	
	rule rdivRelay1(rseState == RDIVIDE1 && count < estimate.getNewTotal-1 && !running);
		Bit#(64) val <- diff.get;
		rdividescalar.put(val);
		count <= count + 1;
	endrule
	
	rule startRDiv1(rseState == RDIVIDE1 && count == estimate.getNewTotal -1);
		count <= 0;
		rdividescalar.setScalar('b0011111111110000000000000000000000000000000000000000000000000000, True);
		rdividescalar.start;
		running <= True;
	endrule
	
	rule endRDiv1(rseState == RDIVIDE1 && rdividescalar.hasRDiv());
		rseState <= RDIVIDE2;
		count <= 0;
		running <= False;
`ifdef BSIM
		$display("Relaying to RDivide2.\n");
`endif
	endrule 
	
	rule rdivRelay2(rseState == RDIVIDE2 && count < estimate.getNewTotal-1  && !running);
		Bit#(64) val <- rdividescalar.get;
		rdividescalar.put(val);
		count <= count + 1;
	endrule
	
	rule startRDiv2(rseState == RDIVIDE2 && count == estimate.getNewTotal -1);
		count <= 0;
		rdividescalar.setScalar('b0100000000000000000000000000000000000000000000000000000000000000, False);
		rdividescalar.start;
		running <= True;
	endrule
	
	rule endRDiv2(rseState == RDIVIDE2 && rdividescalar.hasRDiv());
		rseState <= MEDFILT1;
		count <= 0;
		running <= False;
`ifdef BSIM
		$display("Relaying to MedFilt1.\n");
`endif
	endrule
	
	rule med1Relay(rseState == MEDFILT1 && count < estimate.getNewTotal-1   && !running);
		Bit#(64) val <- rdividescalar.get;
		medFilt1.put(val);
		timeQ.enq(val);
		count <= count + 1;
	endrule
	
	rule startMedFilt1(rseState == MEDFILT1 && count == estimate.getNewTotal-1);
		count <= 0;
		medFilt1.start;
		running <= True;
	endrule
	
	rule endMedFilt1(rseState == MEDFILT1 && medFilt1.hasMed1());
		rseState <= INIT;
		count <= 0;
		rseDone <= True;
		running <= False;
	endrule
	
	method Bool hasRSE;
		return rseDone;
	endmethod
	
	method Action put(Bit#(64) data);
		inputQ.enq(data);
	endmethod
	
	method Action loadSgolay(Bit#(64) weight);
		sgolayFilt.loadSgolay(weight);
	endmethod
	
	method Action loadAxis(Bit#(64) inc);
		estimate.loadAxis(inc);
	endmethod
	
	method Bit#(CountLen#(datalen)) getNewTotal;
		return estimate.getNewTotal;
	endmethod
	
	method ActionValue#(Bit#(64)) getTime;
		Bit#(64) val = timeQ.first;
		timeQ.deq;
        return val;
    endmethod
	
	method ActionValue#(Bit#(64)) getSpeed;
		Bit#(64) val <- medFilt1.get;
        return val;
    endmethod
	
	method Action start;
		rseState <= STANDARDIZE1;
`ifdef BSIM
		$display("Starting RotorSpeedEstimate.");
		$display("Relaying to Standardize1.\n");
`endif
	endmethod

endmodule: mkRotorSpeedEstimate