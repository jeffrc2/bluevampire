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

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, ADD, DIV, CUM} CumTrapzState deriving(Bits,Eq);

interface CumTrapzIfc#(numeric type datalen);
//INIT
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasCum();
	method ActionValue#(Bit#(64)) get;
endinterface

module mkCumTrapz(CumTrapzIfc#(datalen));
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FpPairIfc#(64) add <- mkFpAdd64(clocked_by curClk, reset_by curRst);
	FpPairIfc#(64) div <- mkFpDiv64(clocked_by curClk, reset_by curRst);
	Reg#(Bit#(CountLen#(datalen))) total <- mkReg(fromInteger(valueOf(datalen)));
	
	Reg#(CumTrapzState) cumState <- mkReg(INIT);
	
	FIFOF#(Bit#(64)) cumQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	Reg#(Bit#(64)) prev <- mkReg(0);
	Reg#(Bit#(64)) cum <- mkReg(0);
	
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	Reg#(Bool) addQueued <- mkReg(False);
	Reg#(Bool) cumDone <- mkReg(False);
	
	rule startAdd(cumState == ADD && !addQueued);
		if (count == 0) begin
			Bit#(64) val = cumQ.first;
			cumQ.deq;
			prev <= val;
			count <= count + 1;
			Bit#(64) zero = 0;
			outQ.enq(zero);
		end else if (count < total) begin
			Bit#(64) val = cumQ.first;
			cumQ.deq;
			add.enq(val, prev);
			prev <= val;
			addQueued <= True;
		end else begin
			$display("Cumulative Trapezoidal Numerical Integration Complete. \n");
			cumDone <= True;
			cumState <= INIT;
		end
	endrule

	rule startDiv(cumState == ADD && addQueued);
		Bit#(64) val = add.first;
		add.deq;
		Bit#(64) two = 'b0100000000000000000000000000000000000000000000000000000000000000;
		div.enq(val, two);
		addQueued <= False;	
		cumState <= DIV;
	endrule
	
	rule startCum(cumState == DIV);
		Bit#(64) val = div.first;
		div.deq;
		add.enq(val, cum);
		cumState <= CUM;
	endrule
	
	rule endCum(cumState == CUM);
		Bit#(64) val = add.first;
		//$display( "CumTrapz Position: %u Binary Value: %b \n", count, val);
		add.deq;
		outQ.enq(val);
		cum <= val;
		count <= count + 1;
		cumState <= ADD;
	endrule
	
	method Action start;
		$display( "Starting Cumulative Trapezoidal Numerical Integration. \n");
		cumState <= ADD;
	endmethod
	
	method Bool hasCum();
		return cumDone;
	endmethod
	
	method Action put(Bit#(64) data);
		cumQ.enq(data);
	endmethod
	
	method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
endmodule : mkCumTrapz