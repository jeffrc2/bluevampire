import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;
//
import DotProduct::*;
import Filter::*;
//

typedef 5 FilterALen;
typedef 5 FilterBLen;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, FILTER} ButterState deriving(Bits,Eq);

interface ButterFiltIfc#(numeric type datalen);
//INIT
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasButter;
	method ActionValue#(Bit#(64)) get;
endinterface

module mkButterFilt(ButterFiltIfc#(datalen));

	Reg#(ButterState) butterState <- mkReg(INIT);
	FilterIfc#(datalen, FilterALen, FilterBLen) filter <- mkFilter;
	FIFOF#(Bit#(64)) butterQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	//Reg#(Bit#(CountLen#(datalen))) bitTotal <- mkReg(fromInteger(valueOf(datalen)));
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	
	Reg#(Bool) filterQueued <- mkReg(False);
	Reg#(Bool) butterDone <- mkReg(False);
	
	rule filterRelay(butterState == FILTER && count < fromInteger(valueOf(datalen)) && !filterQueued);
		Bit#(64) val = butterQ.first;
		butterQ.deq;
		filter.put(val);
		count <= count + 1;
	endrule
	
	rule startFilter(butterState == FILTER && count == fromInteger(valueOf(datalen)));
		$display("Filter Started. \n");
		count <= 0;
		filter.start;
		filterQueued <= True;
	endrule
	
	rule endFilter(butterState == FILTER && filterQueued && filter.hasFiltered());
		$display("Filter done");
		filterQueued <= False;
		butterDone <= True;
		butterState <= INIT;
	endrule

	function Bit#(64) loadButterA(Integer i);
		Bit#(64) val;
		if (i == 0)      val =  'b0011111111110000000000000000000000000000000000000000000000000000;//1
		else if (i == 1) val =  'b1100000000001111100110110001111110110111101110111011100000100010;//-3.950744090477216
		else if (i == 2) val = 	'b0100000000010111011010011110110010100000010010001101111011101010;//5.853441719482115
		else if (i == 3) val = 	'b1100000000001110110101100100101001000100110111010000100111000011;//-3.854633844371365
		else if (i == 4) val =  'b0011111111101110011101100100001100110010001111101000111110100100;//0.951936338552049
		else val = 0;
		return val;
	endfunction
	
	function Bit#(64) loadButterB(Integer i);
		Bit#(64) val;
		if (i == 0)      val = 'b0011111111101111001110001011010100000010011011101000100011101100;//0.975672249555172
		else if (i == 1) val = 'b1100000000001111001110001011010100000010011011101000100011101000;//-3.902688998220686
		else if (i == 2) val = 'b0100000000010111011010101000011111000001110100101110011010101110;//5.85403349733103
		else if (i == 3) val = 'b1100000000001111001110001011010100000010011011101000100011101000;//-3.902688998220686
		else if (i == 4) val = 'b0011111111101111001110001011010100000010011011101000100011101100;//0.975672249555172
		else val = 0;
		return val;
	endfunction
	
	method Action put(Bit#(64) data);
		butterQ.enq(data);
	endmethod
	
	method Action start;
		$display( "Starting Butter Filter. \n");
		butterState <= FILTER;
		Vector#(FilterALen, Bit#(64)) butterVecA = genWith(loadButterA);
		Vector#(FilterBLen, Bit#(64)) butterVecB = genWith(loadButterB);
		filter.setCoeffVectors(butterVecA, butterVecB);
	endmethod
	
	
	method Bool hasButter();
		return butterDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
		Bit#(64) val <- filter.get;
        return val;
    endmethod

endmodule:mkButterFilt