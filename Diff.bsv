import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, DIFF} DiffState deriving(Bits,Eq);

interface DiffIfc#(numeric type datalen);
//INIT
	method Action setTotal(Bit#(CountLen#(datalen)) tot);
	method Action put(Bit#(64) data);
	method Action start;
//SUMMATE
	method Bool hasDiff;
	method Action clear();
    method ActionValue#(Bit#(64)) get;
endinterface

module mkDiff(DiffIfc#(datalen));

	Reg#(Bit#(64)) prev <- mkReg(0);
	
	FIFOF#(Bit#(64)) diffQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)) - 1);
	
	//Reg#(Bit#(CountLen#(datalen))) total <- mkReg(200000);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	FpPairIfc#(64) sub <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	Reg#(Bool) diffFlag <- mkReg(False);
	
	Reg#(Bit#(CountLen#(datalen))) total <- mkReg(fromInteger(valueOf(datalen)));
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
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
	
	rule endDiff(diffState == DIFF && count == fromInteger(valueOf(datalen)));
		diffDone <= True;
		diffState <= INIT;
		count <= 0;
	endrule
	
	method Bool hasDiff;
		return diffDone;
	endmethod
	
	method Action setTotal(Bit#(CountLen#(datalen)) tot);
		total <= tot;
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