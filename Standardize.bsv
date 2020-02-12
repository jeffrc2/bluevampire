import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;


//
import Summate::*;
//

import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

//`define STANDARDIZE_DEBUG

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, SUM,AVERAGE,STANDARDIZE} StandardizeState deriving(Bits,Eq);

interface StandardizeIfc#(numeric type datalen);
//INIT
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasStd();
	method ActionValue#(Bit#(64)) get;
	method Action clear;
endinterface

module mkStandardize(StandardizeIfc#(datalen));
	SummateIfc#(datalen) summate <- mkSummate; 
	
	Reg#(StandardizeState) stdState <- mkReg(INIT);
	
	FIFOF#(Bit#(64)) stdQ1 <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) stdQ2 <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	
	//Reg#(Bit#(20)) bitTotal <- mkReg(fromInteger(valueOf(datalen)));
	Reg#(Bit#(64)) dblTotal <- mkReg('b0100000100001000011010100000000000000000000000000000000000000000);
	
	Reg#(Bit#(64)) average <- mkReg(0);
	Reg#(Bool) divFlag <- mkReg(False);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Reg#(Bool) subQueued <- mkReg(False);
	
	Reg#(Bool) stdDone <- mkReg(False);

	FpPairIfc#(64) div <- mkFpDiv64(clocked_by curClk, reset_by curRst);
	FpPairIfc#(64) sub <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	rule summateRelay(stdState == SUM && count < fromInteger(valueOf(datalen)));
		Bit#(64) val = stdQ1.first;
		stdQ1.deq;
		summate.put(val);
		count <= count + 1;
	endrule
	
	rule startSummate(stdState == SUM && count == fromInteger(valueOf(datalen)));
		count <= 0;
		summate.start;
	endrule
	
	rule startAverage(stdState ==  SUM && summate.hasSum());
		Bit#(64) val = summate.getSum();
		stdState <= AVERAGE;
		div.enq(val, dblTotal);
`ifdef STANDARDIZE_DEBUG
		$display("Dividing. %b / %b \n", val, dblTotal);
`endif
	endrule
	
	rule endAverage(stdState == AVERAGE);
		Bit#(64) val = div.first;
		div.deq;
		stdState <= STANDARDIZE;
		average <= val;
		count <= 0;
`ifdef STANDARDIZE_DEBUG
		$display("Average Binary Value: %b \n", val);
`endif
	endrule
	
	rule startStd(stdState == STANDARDIZE && !subQueued);
		if (count < fromInteger(valueOf(datalen))) begin
			Bit#(64) op = stdQ2.first;
			stdQ2.deq;
			sub.enq(op, average);
			subQueued <= True;
		end
		if (count == fromInteger(valueOf(datalen))) begin
			stdDone <= True;
			stdState <= INIT;
`ifdef BSIM
			$display("Standardize Complete. \n");
`endif
		end
	endrule
	
	rule exitStd(stdState == STANDARDIZE && subQueued);
		Bit#(64) val = sub.first;
		sub.deq;
		outQ.enq(val);
		count <= count + 1;
		subQueued <= False;
`ifdef STANDARDIZE_DEBUG
		$display( "Standardized op no. %d", count);
		$display( "Standardized Binary Value: %b \n", val);
`endif
	endrule
	
	method Action put(Bit#(64) data);
		stdQ1.enq(data);
		stdQ2.enq(data);
	endmethod
	
	method Action start;
`ifdef BSIM
		$display( "Starting Standardize. \n");
`endif
		stdState <= SUM;
	endmethod
	
	method Bool hasStd();
		return stdDone;
	endmethod
	
	method Action clear;
		summate.clear;
		stdState <= INIT;
		stdQ1.clear();
		stdQ2.clear();
		outQ.clear();
		count <= 0;
		divFlag <= False;
		average <= 0;
		subQueued <= False;
		stdDone <= False;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
endmodule:mkStandardize


