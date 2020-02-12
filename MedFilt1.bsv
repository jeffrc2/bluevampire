import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import FloatingPoint::*;
import Float32::*;
import Float64::*;

typedef TLog#(len) CountLen#(numeric type len);
typedef TAdd#(TLog#(len),1) CountPlusPlusLen#(numeric type len);

typedef 4 MedianWindow;

typedef enum {INIT, MED, SUM, DIV} MedFilt1State deriving(Bits,Eq);

interface MedFilt1Ifc#(numeric type datalen);
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(CountLen#(datalen)) tot);
	method Action start;
//MEDFILT1
	method Bool hasMed1;
    method ActionValue#(Bit#(64)) get;
endinterface

module mkMedFilt1(MedFilt1Ifc#(datalen));

//Apply a one dimensional median filter with a window size of n to the data x, which must be real, double and full.
//For n = 2m+1, y(i) is the median of x(i-m:i+m).
//For n = 2m, y(i) is the median of x(i-m:i+m-1). 
//n = 4
//When n is even, y(k) is the median of x(k-n/2:k+(n/2)-1). In this case, medfilt1 sorts the numbers and takes the average of the two middle elements of the sorted list.
	Reg#(MedFilt1State) medState <- mkReg(INIT);
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;

	FpPairIfc#(64) add <- mkFpAdd64(clocked_by curClk, reset_by curRst);
	FpPairIfc#(64) div <- mkFpDiv64(clocked_by curClk, reset_by curRst);

	FIFOF#(Bit#(64)) med1Q <- mkSizedFIFOF(fromInteger(valueOf(datalen))-1);
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen))-1);
	
	Vector#(MedianWindow, Reg#(Bit#(64))) filtVec <- replicateM(mkReg(0));
	
	Reg#(Bit#(CountLen#(datalen))) total <- mkReg(fromInteger(valueOf(datalen))-1);
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	
	Reg#(Bit#(CountLen#(MedianWindow))) max <- mkReg(0);
	Reg#(Bit#(CountLen#(MedianWindow))) min <- mkReg(0);
	
	Reg#(Bool) medDone <- mkReg(False);
	
	

	function Double convertBit2Dbl(Bit#(64) dbl);
		Bool sign = dbl[63] == 1;
		Bit#(11) e = truncate(dbl>>52);
		Bit#(52) s = truncate(dbl);
		Double val = Double{sign: sign, exp: e, sfd: s};
		return val;
	endfunction

	
	function Vector#(2, Bit#(64)) getMedianTwo(Vector#(MedianWindow, Bit#(64)) vecIn);
		Vector#(2, Bit#(64)) vecOut = replicate(0);
		Bit#(CountPlusPlusLen#(MedianWindow)) max_pos = 0;
		Bit#(CountPlusPlusLen#(MedianWindow)) min_pos = 0;
		Bit#(64) max_cur = vecIn[0];
		Bit#(64) min_cur = vecIn[0];
		Bit#(64) min_prev = vecIn[0];
		Bit#(64) max_prev = vecIn[0];
		Bit#(64) val_in;
		Bit#(CountPlusPlusLen#(MedianWindow)) index;
		for (index = 1; index < fromInteger(valueOf(MedianWindow)); index = index + 1)
			val_in = select(vecIn,index);
			Double max_dbl = convertBit2Dbl(max_cur);
			Double min_dbl = convertBit2Dbl(min_cur);
			Double val_dbl = convertBit2Dbl(val_in);
			if (compareFP(max_dbl, val_dbl) == LT) begin //if max is less than current val
				max_prev = max_cur;
				max_pos = index;
				max_cur = val_in;
			end
			if (compareFP(min_dbl, val_dbl) == GT) begin //if min is greater than current val
				min_prev = min_cur;
				min_pos = index;
				min_cur = val_in;
			end
		if ((max_pos == 0 && min_pos == 1) || (max_pos == 1 || min_pos == 0)) begin
			vecOut[0] = vecIn[2];
			vecOut[1] = vecIn[3];
		end else if ((max_pos == 1 && min_pos == 2) || (max_pos == 2 || min_pos == 1)) begin
			vecOut[0] = vecIn[0];
			vecOut[1] = vecIn[3];
		end else if ((max_pos == 2 && min_pos == 3) || (max_pos == 3 || min_pos == 2)) begin
			vecOut[0] = vecIn[0];
			vecOut[1] = vecIn[1];
		end else if ((max_pos == 3 && min_pos == 0) || (max_pos == 0 || min_pos == 3)) begin
			vecOut[0] = vecIn[1];
			vecOut[1] = vecIn[2];
		end
		return vecOut;
	endfunction
	
	rule startMed(medState == MED && count < total+1);
		Bit#(64) val = 0;
		if (count < total) begin
			val = med1Q.first;
			med1Q.deq;
		end
		Vector#(MedianWindow, Bit#(64)) vecIn = shiftInAt0(readVReg(filtVec), val);
		writeVReg(filtVec, vecIn);
		if (count == 0) begin
			count <= count + 1;
		end else begin
			Vector#(2, Bit#(64)) vecMed = getMedianTwo(vecIn);
			add.enq(vecMed[0], vecMed[1]);
			medState <= SUM;
		end	
	endrule
	
	rule startDiv(medState == SUM);
		Bit#(64) two = 'b0100000000000000000000000000000000000000000000000000000000000000;
		Bit#(64) val = add.first;
		add.deq;
		div.enq(val,two);
		medState <= DIV;
	endrule
	
	rule endDiv(medState == DIV);
		Bit#(64) val = div.first;
		div.deq;
		outQ.enq(val);
		count <= count + 1;
		medState <= MED;
	endrule

	rule endMed(medState == MED && count == total+1);
		medState <= INIT;
		medDone <= True;
	endrule
	
	method Action setTotal(Bit#(CountLen#(datalen)) tot);
		total <= tot-1;
	endmethod

	method Action put(Bit#(64) data);
		med1Q.enq(data);
	endmethod

	method Bool hasMed1;
		return medDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Median Filter 1D. \n");
		medState <= MED;
	endmethod


endmodule:mkMedFilt1