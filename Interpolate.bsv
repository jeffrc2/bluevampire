import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

import Float32::*;
import Float64::*;
import FloatingPoint::*;

typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, INTERPOLATE, STAGE1, STAGE2, STAGE3, STAGE4, STAGE5} InterpolateState deriving(Bits,Eq);

interface InterpolateIfc#(numeric type datalen, numeric type tevenlen);
//INIT
	method Action putTime(Bit#(64) data);
	method Action putSpeed(Bit#(64) data);
	method Action loadTime(Bit#(64) inc);
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
	method Action start;
//SUMMATE
	method Bool hasInterpolate;
    method ActionValue#(Bit#(64)) get;
endinterface

module mkInterpolate(InterpolateIfc#(datalen, tevenlen));
	
	FIFOF#(Bit#(64)) intTQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) intSQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) timeQ <- mkSizedFIFOF(fromInteger(valueOf(tevenlen)));
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Reg#(Bit#(CountLen#(tevenlen))) total <- mkReg(fromInteger(valueOf(tevenlen)));
	Reg#(Bit#(CountLen#(tevenlen))) subcount <- mkReg(0);
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	Reg#(InterpolateState) intState <- mkReg(INIT);
	Reg#(Bool) intDone <- mkReg(False);
	
	Reg#(Bit#(64)) prev_t_val <- mkReg(0);
	Reg#(Bit#(64)) prev_s_val <- mkReg(0);
	
	Reg#(Bit#(64)) cur_t_val <- mkReg(0);
	Reg#(Bit#(64)) cur_s_val <- mkReg(0);
	Reg#(Bit#(64)) cur_t_even <- mkReg(0);
	
	//stage1
	FpPairIfc#(64) sub1a <- mkFpSub64(clocked_by curClk, reset_by curRst); //tp - tt_prev
	FpPairIfc#(64) sub1b <- mkFpSub64(clocked_by curClk, reset_by curRst);//tt- tp
	
	//stage2
	FpPairIfc#(64) div2 <- mkFpDiv64(clocked_by curClk, reset_by curRst);//(tp-tt_prev)/(tt-tp) || sub1a/sub1b
	
	//stage3
	FpPairIfc#(64) mult3 <- mkFpMult64(clocked_by curClk, reset_by curRst);//(tp-tt_prev)/(tt-tp) * ts || div2*ts
	FpPairIfc#(64) add3 <- mkFpAdd64(clocked_by curClk, reset_by curRst);//1+(tp-tt_prev)/(tt-tp) || 1+div2
	
	//stage4
	FpPairIfc#(64) add4 <- mkFpAdd64(clocked_by curClk, reset_by curRst);//ts_prev+(tp-tt_prev)/(tt-tp)*ts || ts_prev + mult3
	
	//stage5
	FpPairIfc#(64) div5 <- mkFpDiv64(clocked_by curClk, reset_by curRst);//(ts_prev+(tp-tt_prev)/(tt-tp)*ts)/(1+(tp-tt_prev)/(tt-tp)) || add4/add3
	
	function Double convertBit2Dbl(Bit#(64) dbl);
		Bool sign = dbl[63] == 1;
		Bit#(11) e = truncate(dbl>>52);
		Bit#(52) s = truncate(dbl);
		Double val = Double{sign: sign, exp: e, sfd: s};
		return val;
	endfunction
	
	rule startInterpolate(intState == INTERPOLATE && subcount < fromInteger(valueOf(tevenlen)));
		if (subcount == 0) begin
			Bit#(64) t_even = timeQ.first;
			timeQ.deq;
			cur_t_even <= t_even;
			Bit#(64) t_val = intTQ.first;
			cur_t_val <= t_val;
			intTQ.deq;
			Bit#(64) s_val = intSQ.first;
			intSQ.deq;
			cur_s_val <= t_even;
			count <= count + 1;
		end else if (subcount < fromInteger(valueOf(tevenlen))) begin
			Bit#(64) cur_t = cur_t_val;
			Bit#(64) cur_s = cur_s_val; 
			Double dbl_cur_t_even = convertBit2Dbl(cur_t_even); 
			Double dbl_cur_t_val = convertBit2Dbl(cur_t); 
			Bit#(64) t_even;
			Bit#(64) t_val;
			Bit#(64) s_val;
			Bit#(64) t_prev;
			Bit#(64) s_prev;
			if (compareFP(dbl_cur_t_val, dbl_cur_t_even) == LT) begin //t_even less than t_val, meaning need to get next t_even
				t_even = timeQ.first;
				timeQ.deq;
				t_val = cur_t_val;
				s_val = cur_s_val;
				t_prev = prev_t_val;
				s_prev = prev_s_val;
			end else begin //t_even greater than t_val, meaning need to get next t_val
				t_val = intTQ.first;
				intTQ.deq;
				s_val = intSQ.first;
				intSQ.deq;
				t_even = cur_t_even;
				s_prev = cur_t_val;
				t_prev = cur_s_val;
				count <= count + 1;
			end
			if (compareFP(convertBit2Dbl(t_prev), convertBit2Dbl(t_even)) == LT && compareFP(convertBit2Dbl(t_val), convertBit2Dbl(t_even)) == GT && compareFP(convertBit2Dbl(t_prev), convertBit2Dbl(0)) != EQ) begin
				//t_prev < t_even && t_val > t_even && t_prev != 0
				//load into the ultra mess
				sub1a.enq(t_even, t_prev);
				sub1b.enq(t_val, t_even);
				intState <= STAGE1;
			end else begin
				outQ.enq(0);
			end
			prev_t_val <= t_prev;
			prev_s_val <= s_prev;
			cur_t_val <= t_val;
			cur_s_val <= s_val;
			cur_t_even <= t_even;
			//(target_rotor_time(i-1) < time_point && time_point < target_rotor_time(i))
			//cur_t_val < t_even && t_val > t_even
		end
		subcount <= subcount + 1;
	endrule
	
	rule endInterpolate(intState == INTERPOLATE && subcount == fromInteger(valueOf(tevenlen)));
		intDone <= True;
	endrule
	
	
	rule startStage2(intState == STAGE1);
		Bit#(64) a = sub1a.first;
		sub1a.deq;
		Bit#(64) b = sub1b.first;
		sub1b.deq;
		div2.enq(a,b);
		intState <= STAGE2;
	endrule
	
	rule startStage3(intState == STAGE2);
		Bit#(64) val = div2.first;
		div2.deq;
		Bit#(64) one = 'b0011111111110000000000000000000000000000000000000000000000000000;
		mult3.enq(val, cur_t_val);
		add3.enq(val, one);
		intState <= STAGE3;
	endrule
	
	rule startStage4(intState == STAGE3);
		Bit#(64) val = mult3.first;
		mult3.deq;
		add4.enq(val, prev_t_val);
		intState <= STAGE4;
	endrule
	
	rule startStage5(intState == STAGE4);
		Bit#(64) three = add3.first;
		add3.deq;
		Bit#(64) four = add4.first;
		add4.deq;
		div5.enq(four, three);
		intState <= STAGE5;
	endrule
	
	rule endStage5(intState == STAGE5);
		Bit#(64) val = div5.first;
		div5.deq;
		outQ.enq(val);
		intState <= INTERPOLATE;
	endrule
	
	method Action setTotal(Bit#(CountLen#(tevenlen)) tot);
		total <= tot;
	endmethod
	
	method Action putTime(Bit#(64) data);
		intTQ.enq(data);
	endmethod
	
	method Action putSpeed(Bit#(64) data);
		intSQ.enq(data);
	endmethod
	
	method Bool hasInterpolate;
		return intDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action loadTime(Bit#(64) inc);
		timeQ.enq(inc);
	endmethod	
	
	method Action start;
		$display( "Starting Interpolate. \n");
		intState <= INTERPOLATE;
	endmethod
endmodule:mkInterpolate