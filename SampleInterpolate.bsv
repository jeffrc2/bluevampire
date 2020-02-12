import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

//
import Interpolate::*;
import Radian::*;
import Square::*;
//
import BRAM::*;
import BRAMFIFO::*;
import Float32::*;
import Float64::*;

import FloatingPoint::*;

typedef 4 ZeroLen;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, INTERPOLATE, RANGE, TRIM, RADIAN, SQUARECUMTRAPZ, SIN, ELEMMULT} State deriving(Bits,Eq);

interface SampleInterpolateIfc#(numeric type datalen, numeric type tevenlen);
//INIT
	method Action putTime(Bit#(64) data);
	method Action putSpeed(Bit#(64) data);
	method Action start;
	method Bool hasSI;
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
	method Action loadTime(Bit#(64) inc);	
	method ActionValue#(Bit#(64)) get;
endinterface

module mkSampleInterpolate(SampleInterpolateIfc#(datalen, tevenlen));
	
	Reg#(State) siState <- mkReg(INIT);
	Reg#(Bool) foundMin <- mkReg(False);
	Reg#(Bool) foundMax <- mkReg(False);
	
	Reg#(Double) fmin <- mkReg(0);
	Reg#(Double) fmax <- mkReg(0);
	
	
	Reg#(Bit#(CountLen#(tevenlen))) minIndex <- mkReg(0);
	Reg#(Bit#(CountLen#(tevenlen))) maxIndex <- mkReg(0);
	InterpolateIfc#(datalen, tevenlen) interpolate <- mkInterpolate;
	RadianIfc#(tevenlen) radian <- mkRadian;
	SquareIfc#(tevenlen) square <- mkSquare;
	
	FIFOF#(Bit#(64)) timeQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen)));
	
	FIFOF#(Bit#(64)) speedEQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen)));
	FIFOF#(Bit#(64)) timeEQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen)));
	
	Reg#(Bit#(CountLen#(tevenlen))) count <- mkReg(0);
	Reg#(Bit#(CountLen#(tevenlen))) total <- mkReg(0);
	
	Reg#(Bool) running <- mkReg(False);
	
	function Double convertBit2Dbl(Bit#(64) dbl);
		Bool sign = dbl[63] == 1;
		Bit#(11) e = truncate(dbl>>52);
		Bit#(52) s = truncate(dbl);
		Double val = Double{sign: sign, exp: e, sfd: s};
		return val;
	endfunction
	
	rule endInterpolate(siState == INTERPOLATE && interpolate.hasInterpolate);
		siState <= TRIM;
		count <= 0;
		total <= 0;
	endrule
	
	rule startTrim(siState == TRIM && count < fromInteger(valueOf(tevenlen)) && !running);
		Bit#(64) t_even = timeQ.first;
		Bit#(64) speed_even <- interpolate.get;
		Double t_dbl = convertBit2Dbl(t_even);
		if ((compareFP(t_dbl, fmin) == GT||compareFP(t_dbl, fmin) == EQ) && (compareFP(t_dbl, fmax) == LT || compareFP(t_dbl, fmax) == EQ)) begin
			radian.put(speed_even);
			//cumTrapzCoord.putX(t_even);
			total <= total+1;
		end
		count <= count + 1;
	endrule
	
	rule startRadian(siState == TRIM && count == fromInteger(valueOf(tevenlen)));
		siState <= RADIAN;
		radian.setTotal(total);
		square.setTotal(total);
		//cumTrapzCoord.setTotal(total);
		radian.start;
		running <= True;
	endrule
	
	rule endRadian(siState == RADIAN && radian.hasRadian);
		siState <= SQUARECUMTRAPZ;
		count <= 0;
		running <= False;
	endrule
	
	rule relaySquareCumTrapz(siState == SQUARECUMTRAPZ && count < total && !running);
		Bit#(64) val <- radian.get;
		square.put(val);
		//cumTrapzCoord.putY(val);
		count <= count + 1;
	endrule
	
	rule startSquareCumTrapz(siState == SQUARECUMTRAPZ && count == total);
		square.start;
		//cumTrapzCoord.start;
		running <= True;
	endrule
	
	rule endSquareCumTrapz(siState == SQUARECUMTRAPZ && square.hasSquare);// && cumTrapzCoord.hasCum);
		siState <= SIN;
	endrule

	method Action putTime(Bit#(64) data);
		Bit#(64) tmin = 'b0100000001010100000000000000000000000000000000000000000000000000; //first element >= tmin 80;
		Bit#(64) tmax = 'b0100000001010111110000000000000000000000000000000000000000000000; //last element <= tmax 95;
		Double min = convertBit2Dbl(tmin);
		Double max = convertBit2Dbl(tmax);
		Double val = convertBit2Dbl(data);
		if (!foundMin && (compareFP(val, min) == GT || compareFP(val, min) == EQ)) begin
			foundMin <= True;
			interpolate.putTime(data);
			minIndex <= count;
			fmin <= val;
			fmax <= val;
		end else if (foundMin) begin
			if (compareFP(val, fmin) == LT) begin
				fmin <= val;
			end
			interpolate.putTime(data);
		end
		if (foundMin && (compareFP(val, max) == LT || compareFP(val, max) == EQ)) begin
			maxIndex <= count;
			foundMax <= True;
			if (compareFP(val, fmax) == GT) begin
				fmax <= val;
			end 
		end else if (!foundMax && foundMin) begin
			if (compareFP(val, fmax) == GT) begin
				fmax <= val;
			end 
		end
		count <= count+1;
	endmethod
	
	method Action putSpeed(Bit#(64) data);
		interpolate.putSpeed(data);
	endmethod
	
	method Action start;
		siState <= INTERPOLATE;
		count <= 0;
		Bit#(CountLen#(tevenlen)) newLen = maxIndex - minIndex;
		if (!foundMax || !foundMin) begin
			$display("Uh oh, min/max not found.");
		end
		interpolate.start;
		interpolate.setTotal(newLen);
`ifdef BSIM
		$display("Starting RotorSpeedEstimate.");
		$display("Relaying to Standardize1.\n");
`endif
	endmethod

	method Action loadTime(Bit#(64) inc);
		interpolate.loadTime(inc);
		timeQ.enq(inc);
	endmethod

	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
		total <= tot;
	endmethod

endmodule: mkSampleInterpolate