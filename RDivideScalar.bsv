import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;

typedef enum {INIT, DIV} RDivideScalarState deriving(Bits,Eq);

interface RDivideScalarIfc;
//INIT
	method Action put(Bit#(64) data);
	method Action setScalar(Bit#(64) scalar, Bool position);
	method Action start;
//SUMMATE
	method Bool hasRDiv;
    method ActionValue#(Bit#(64)) get;
endinterface

module mkRDivideScalar(RDivideScalarIfc);

	Reg#(Bit#(64)) rDivScalar <- mkReg(0);
	
	FIFOF#(Bit#(64)) rdivQ <- mkSizedFIFOF(199999);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(199999);
	
	Reg#(Bit#(20)) total <- mkReg(199999);
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Reg#(Bool) numDen <- mkReg(False);
	
	FpPairIfc#(64) div <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	Reg#(Bool) divFlag <- mkReg(False);
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(RDivideScalarState) divState <- mkReg(INIT);
	Reg#(Bool) rdivDone <- mkReg(False);
	
	rule startDiv(divState == DIV && count < total && !divFlag);
		rdivQ.deq;
		Bit#(64) val = rdivQ.first;
		if (numDen) begin
			div.enq(rDivScalar, val);
		end	else begin
			div.enq(val,rDivScalar); 
		end
		divFlag <= True;
	endrule
	
	rule endDiv(divState == DIV && divFlag);
		Bit#(64) val = div.first;
		div.deq;
		divFlag <= False;
		count <= count + 1;
	endrule
	
	rule endRDiv(divState == DIV && count == total);
		rdivDone <= True;
		divState <= INIT;
		count <= 0;
	endrule
	
	method Action setScalar(Bit#(64) scalar, Bool position);
		rDivScalar <= scalar;
		numDen <= position;
	endmethod
	
	method Action put(Bit#(64) data);
		rdivQ.enq(data);
	endmethod
	
	method Bool hasRDiv;
		return rdivDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Filter. \n");
		divState <= DIV;
	endmethod
endmodule:mkRDivideScalar