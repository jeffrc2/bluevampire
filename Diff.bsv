import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;

typedef enum {INIT, DIFF} DiffState deriving(Bits,Eq);

interface DiffIfc;
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(20) tot);
	method Action start;
//SUMMATE
	method Bool hasDiff;
	method Action clear();
    method ActionValue#(Bit#(64)) get;
endinterface

module mkDiff(DiffIfc);

	Reg#(Bit#(64)) prev <- mkReg(0);
	
	FIFOF#(Bit#(64)) diffQ <- mkSizedFIFOF(200000);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(199999);
	
	Reg#(Bit#(20)) total <- mkReg(200000);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	FpPairIfc#(64) sub <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	Reg#(Bool) diffFlag <- mkReg(False);
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(DiffState) diffState <- mkReg(INIT);
	Reg#(Bool) diffDone <- mkReg(False);
	
	rule startSub(diffState == DIFF && count < total && !diffFlag);
		diffQ.deq;
		Bit#(64) val = diffQ.first;
		if (count > 0) begin
			sub.enq(val,prev); 
		end else begin
			count<= count + 1;
		end
		prev <= val;
		diffFlag <= True;
	endrule
	
	rule endSub(diffState == DIFF && diffFlag);
		Bit#(64) val = sub.first;
		sub.deq;
		diffFlag <= False;
		count <= count + 1;
	endrule
	
	rule endDiff(diffState == DIFF && count == total);
		diffDone <= True;
		diffState <= INIT;
		count <= 0;
	endrule
	
	method Bool hasDiff;
		return diffDone;
	endmethod
	
	method Action put(Bit#(64) data);
		diffQ.enq(data);
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Filter. \n");
		diffState <= DIFF;
	endmethod
endmodule:mkDiff