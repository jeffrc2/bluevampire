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

typedef enum {INIT, SUM,AVERAGE,STANDARDIZE} StandardizeState deriving(Bits,Eq);

interface StandardizeIfc;
//INIT
	method Action setTotal(Bit#(20) intTot, Bit#(64) dblTot);
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasStd();
	method ActionValue#(Bit#(64)) get;
	method Action clear;
endinterface

module mkStandardize(StandardizeIfc);
	SummateIfc summate <- mkSummate; 
	
	Reg#(StandardizeState) stdState <- mkReg(INIT);
	
	FIFOF#(Bit#(64)) stdQ1 <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) stdQ2 <- mkSizedFIFOF(200000);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(200000);
	
	Reg#(Bit#(20)) count <- mkReg(0);
	
	Reg#(Bit#(20)) bitTotal <- mkReg(200000);
	Reg#(Bit#(64)) dblTotal <- mkReg('b0100000100001000011010100000000000000000000000000000000000000000);
	
	Reg#(Bit#(64)) average <- mkReg(0);
	Reg#(Bool) divFlag <- mkReg(False);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	Reg#(Bool) subQueued <- mkReg(False);
	
	Reg#(Bool) stdDone <- mkReg(False);

	FpPairIfc#(64) div <- mkFpDiv64(clocked_by curClk, reset_by curRst);
	FpPairIfc#(64) sub <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	rule summateRelay(stdState == SUM && count < bitTotal);
		Bit#(64) val = stdQ1.first;
		stdQ1.deq;
		summate.put(val);
		count <= count + 1;
	endrule
	
	rule startSummate(stdState == SUM && count == bitTotal);
		count <= 0;
		summate.start;
	endrule
	
	rule startAverage(stdState ==  SUM && summate.hasSum());
		Bit#(64) val = summate.getSum();
		stdState <= AVERAGE;
		//$display("Dividing. \n");
		div.enq(val, dblTotal);
	endrule
	
	rule endAverage(stdState == AVERAGE);// && divFlag);
		Bit#(64) val = div.first;
		div.deq;
		//$display("Average Binary Value: %b \n", val);
		stdState <= STANDARDIZE;
		average <= val;
		count <= 0;
	endrule
	
	rule startStd(stdState == STANDARDIZE && !subQueued);
		if (count < bitTotal) begin
			Bit#(64) op = stdQ2.first;
			stdQ2.deq;
			sub.enq(op, average);
			subQueued <= True;
		end
		if (count == bitTotal) begin
			$display("Standardize Complete. \n");
			stdDone <= True;
			stdState <= INIT;
		end
	endrule
	
	rule exitStd(stdState == STANDARDIZE && subQueued);
		Bit#(64) val = sub.first;
		sub.deq;
		outQ.enq(val);
		//$display( "Standardized op no. %d", count);
		//$display( "Standardized Binary Value: %b \n", val);
		count <= count + 1;
		subQueued <= False;
	endrule
	
	method Action setTotal(Bit#(20) intTot, Bit#(64) dblTot);
		bitTotal <= intTot;
		dblTotal <= dblTot;
		summate.setTotal(intTot);
	endmethod
	
	method Action put(Bit#(64) data);
		stdQ1.enq(data);
		stdQ2.enq(data);
	endmethod
	
	method Action start;
		$display( "Starting Standardize. \n");
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
		bitTotal <= 200000;
		dblTotal <= 'b0100000100001000011010100000000000000000000000000000000000000000;
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
