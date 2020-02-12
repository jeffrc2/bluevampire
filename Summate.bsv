import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

//`define SUMMATE_DEBUG

typedef TAdd#(TLog#(len),1) CountPlusPlusLen#(numeric type len);

typedef enum {INIT, SUMMATE} SummateState deriving(Bits,Eq);

interface SummateIfc#(numeric type datalen);
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(CountPlusPlusLen#(datalen)) tot);
	method Action start;
//SUMMATE
	method Bool hasSum;
	method Bit#(64) getSum;
	method Action clear();
endinterface

module mkSummate(SummateIfc#(datalen));

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FpPairIfc#(64) add <- mkFpAdd64(clocked_by curClk, reset_by curRst);
	
	FIFOF#(Bit#(64)) sumQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	Reg#(Bit#(64)) sumOperand <- mkReg(0);
	Reg#(Bool) sumOpFlag <- mkReg(False);
	
	Reg#(Bit#(CountPlusPlusLen#(datalen))) count <- mkReg(0);
	Reg#(Bit#(CountPlusPlusLen#(datalen))) total <- mkReg(fromInteger(valueOf(datalen)));
	
	Reg#(Bool) addQueued <- mkReg(False);
	
	Reg#(SummateState) sumState <- mkReg(INIT);
	
	Reg#(Bool) sumDone <- mkReg(False);
	
	rule sumEnq(sumState == SUMMATE && !addQueued && !sumDone);
		if (count < total) begin
			Bit#(64) op = sumQ.first;
			sumQ.deq;
			if (!sumOpFlag) begin 
				//fill operand
				sumOperand <= op;
				if (count != total -1) begin
`ifdef SUMMATE_DEBUG
					$display( "Saving Temp Operand. %b\n", op);
`endif
					sumOpFlag <= True;
				end else begin
					sumDone <= True;
`ifdef SUMMATE_DEBUG
					$display("Final Sum value: %b \n", op);
					$display("Summate Complete.\n");
`endif
				end
			end else begin
`ifdef SUMMATE_DEBUG
				$display( "Adding Operands %b %b", sumOperand, op);
`endif
				add.enq(sumOperand, op);
				sumOpFlag <= False;
				addQueued <= True;
			end
		end
		if (count == (total)) begin
			//$display("Sum value: %b \n", sumOperand);
		end
	endrule
	
	rule sumRecursion(sumState == SUMMATE && addQueued && !sumDone);
		Bit#(64) val = add.first;
		add.deq;
		count <= count + 1;
		sumQ.enq(val);
		addQueued <= False;
`ifdef SUMMATE_DEBUG
		$display( "Addition op no. %d", count);
		$display( "Added Binary Value: %b \n", val);
`endif
	endrule	
	
	method Action setTotal(Bit#(CountPlusPlusLen#(datalen)) tot);
		total <= tot;
	endmethod
	
	method Action put(Bit#(64) data);
		sumQ.enq(data);
	endmethod
	
	method Action start;
		sumState <= SUMMATE;
`ifdef SUMMATE_DEBUG
		$display( "Starting Summate.\n");
`endif
	endmethod
	
	method Bool hasSum();
		return sumDone;
	endmethod
	
	method Bit#(64) getSum();
		return sumOperand;
	endmethod
	
	method Action clear();
		sumOperand <= 0;
		sumQ.clear();
		sumOpFlag <= False;
		addQueued <= False;
		sumState <= INIT;
		sumDone <= False;
		count <= 0;
		total <= fromInteger(valueOf(datalen));
	endmethod
	
endmodule:mkSummate
