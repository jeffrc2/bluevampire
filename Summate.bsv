import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

typedef enum {INIT, SUMMATE} SummateState deriving(Bits,Eq);

interface SummateIfc;
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(20) tot);
	method Action start;
//SUMMATE
	method Bool hasSum;
	method Bit#(64) getSum;
	method Action clear();
endinterface

module mkSummate(SummateIfc);

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FpPairIfc#(64) add <- mkFpAdd64(clocked_by curClk, reset_by curRst);
	
	FIFOF#(Bit#(64)) sumQ <- mkSizedFIFOF(200000);
	
	Reg#(Bit#(64)) sumOperand <- mkReg(0);
	Reg#(Bool) sumOpFlag <- mkReg(False);
	
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(Bit#(20)) total <- mkReg(200000);
	
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
					//$display( "Saving Temp Operand. \n");
					sumOpFlag <= True;
				end else begin
					//$display("Final Sum value: %b \n", op);
					sumDone <= True;
				end
			end else begin
				//$display( "Adding Operands. \n");
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
		//$display( "Addition op no. %d", count);
		//$display( "Added Binary Value: %b \n", val);
		count <= count + 1;
		sumQ.enq(val);
		addQueued <= False;
	endrule	
	
	method Action setTotal(Bit#(20) tot);
		total <= tot;
	endmethod
	
	method Action put(Bit#(64) data);
		if (sumState == INIT) begin
			sumQ.enq(data);
		end else begin
			$display( "Illegal put. \n");
			$finish(1);
		end
	endmethod
	
	method Action start;
		sumState <= SUMMATE;
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
		total <= 200000;
	endmethod
	

	
	
endmodule:mkSummate
