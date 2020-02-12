import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, SQUARE} SquareState deriving(Bits,Eq);

interface SquareIfc#(numeric type tevenlen);
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
	method Action start;
//SUMMATE
	method Bool hasSquare;
    method ActionValue#(Bit#(64)) get;
endinterface

module mkSquare(SquareIfc#(tevenlen));
	
	Reg#(SquareState) sqState <- mkReg(INIT);
	
	FIFOF#(Bit#(64)) sqQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen))-1);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen))-1);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Reg#(Bit#(CountLen#(tevenlen))) total <- mkReg(fromInteger(valueOf(tevenlen)));
	Reg#(Bit#(CountLen#(tevenlen))) count <- mkReg(0);
	Reg#(Bool) sqFlag <- mkReg(False);
	Reg#(Bool) sqDone <- mkReg(False);
	
	FpPairIfc#(64) mult <- mkFpMult64(clocked_by curClk, reset_by curRst);
 
	//'b0100000000011001001000011111101101010100010001000010110100011000; //2*pi
	
	rule startSquare(sqState == SQUARE && count < total && !sqFlag);
		Bit#(64) val = sqQ.first;
		Bit#(64) twopi = 'b0100000000011001001000011111101101010100010001000010110100011000;
		sqQ.deq;
		mult.enq(val, twopi);
		sqFlag <= True;
	endrule
	
	rule endSquare(sqState == SQUARE && sqFlag);
		Bit#(64) val = mult.first;
		mult.deq;
		outQ.enq(val);
		sqFlag <= False;
		count <= count + 1;
	endrule
	
	rule endR(sqState == SQUARE && count == total);
		sqDone <= True;
		sqState <= INIT;
		count <= 0;
	endrule
	
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
		total <= tot;
	endmethod
	
	method Action put(Bit#(64) data);
		sqQ.enq(data);
	endmethod
	
	method Bool hasSquare;
		return sqDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Filter. \n");
		sqState <= SQUARE;
	endmethod
endmodule:mkSquare