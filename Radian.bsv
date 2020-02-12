import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, RAD} RadianState deriving(Bits,Eq);

interface RadianIfc#(numeric type tevenlen);
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
	method Action start;
//SUMMATE
	method Bool hasRadian;
    method ActionValue#(Bit#(64)) get;
endinterface

module mkRadian(RadianIfc#(tevenlen));
	
	Reg#(RadianState) radState <- mkReg(INIT);
	
	FIFOF#(Bit#(64)) radQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen))-1);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen))-1);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Reg#(Bit#(CountLen#(tevenlen))) total <- mkReg(fromInteger(valueOf(tevenlen)));
	Reg#(Bit#(CountLen#(tevenlen))) count <- mkReg(0);
	Reg#(Bool) radFlag <- mkReg(False);
	Reg#(Bool) radDone <- mkReg(False);
	
	FpPairIfc#(64) mult <- mkFpMult64(clocked_by curClk, reset_by curRst);

	//'b0100000000011001001000011111101101010100010001000010110100011000; //2*pi
	
	rule startRad(radState == RAD && count < total && !radFlag);
		Bit#(64) val = radQ.first;
		Bit#(64) twopi = 'b0100000000011001001000011111101101010100010001000010110100011000;
		radQ.deq;
		mult.enq(val, twopi);
		radFlag <= True;
	endrule
	
	rule endRad(radState == RAD && radFlag);
		Bit#(64) val = mult.first;
		mult.deq;
		outQ.enq(val);
		radFlag <= False;
		count <= count + 1;
	endrule
	
	rule endR(radState == RAD && count == total);
		radDone <= True;
		radState <= INIT;
		count <= 0;
	endrule
	
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
		total <= tot;
	endmethod
	
	method Action put(Bit#(64) data);
		radQ.enq(data);
	endmethod
	
	method Bool hasRadian;
		return radDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Filter. \n");
		radState <= RAD;
	endmethod
endmodule:mkRadian