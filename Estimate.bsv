import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;
//
import DotProduct::*;
import Float32::*;
import Float64::*;

//
import FloatingPoint::*;


typedef enum {INIT, CHECK, PROCESS, DIV} EstimateState deriving(Bits,Eq);

interface EstimateIfc;
//INIT
	method Action setTotal(Bit#(20) intTot, Bit#(64) dblTot);
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasEst();
	method ActionValue#(Bit#(64)) get;
	method Action clear;
	
	method Action loadAxis(Bit#(64) inc);
endinterface

module mkEstimate(EstimateIfc);
	Reg#(EstimateState) estState <- mkReg(INIT);
		
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	DotProductIfc#(2) dotProduct <- mkDotProduct;
	FpPairIfc#(64) add <- mkFpAdd64(clocked_by curClk, reset_by curRst);
	FpPairIfc#(64) div <- mkFpDiv64(clocked_by curClk, reset_by curRst);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) timeQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) estQ <- mkSizedFIFOF(200000);
	

	Vector#(2, Reg#(Bit#(64))) numVecA <- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(64))) numVecB <- replicateM(mkReg(0));
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(Bit#(20)) subcount <- mkReg(0);
	Reg#(Bit#(20)) total <- mkReg(200000);
	
	Reg#(Bool) estDone <- mkReg(False);
	
	Reg#(Bool) checkFlag <- mkReg(False);
	Reg#(Bit#(64)) prev <- mkReg(0);
	Reg#(Bit#(64)) past <- mkReg(0);
	
	function Bit#(64) convertBit2Abs(Bit#(64) dbl);
		Bit#(1) pos = 0;
		return {pos, dbl[62:0]};
	endfunction
	
	function Double convertBit2Dbl(Bit#(64) dbl);
		Bool sign = dbl[63] == 1;
		Bit#(11) e = truncate(dbl>>52);
		Bit#(52) s = truncate(dbl);
		Double val = Double{sign: sign, exp: e, sfd: s};
		return val;
	endfunction
	
	rule startCheck(estState == CHECK && !checkFlag && count < total );
		timeQ.deq;
		Bit#(64) inc = timeQ.first;
		estQ.deq;
		Bit#(64) val = estQ.first;
		Double cur = convertBit2Dbl(val);
		Double pre = convertBit2Dbl(prev);
		count <= count + 1;
		Bit#(64) zero = 0;
		Double cp = convertBit2Dbl(zero);
		if (count > 0) begin
			if ((compareFP(pre, cp) == LT && (compareFP(cur, cp) == GT || compareFP(cur, cp) == EQ))  || (compareFP(pre, cp) == GT && (compareFP(cur, cp) == LT || compareFP(cur, cp) == EQ))) begin
				checkFlag <= True;
				numVecA[0] <= inc;
				numVecB[0] <= convertBit2Abs(prev);
				numVecA[1] <= past;
				numVecB[1] <= convertBit2Abs(val);
				add.enq(convertBit2Abs(prev), convertBit2Abs(val));
			end
		end
		prev <= val;
		past <= inc;
	endrule
	
	rule startProcess(estState == CHECK && checkFlag);
		dotProduct.put(readVReg(numVecA), readVReg(numVecB));
		dotProduct.start;
		checkFlag <= False;
		estState <= PROCESS;
	endrule
	
	rule startDiv(estState == PROCESS && dotProduct.hasDP());
		Bit#(64) num = dotProduct.getDP();
		dotProduct.clear();
		Bit#(64) den = add.first;
		add.deq;
		div.enq(num,den);
		estState <= DIV;
	endrule
	
	rule endDiv(estState == DIV);
		Bit#(64) val = div.first;
		div.deq;
		outQ.enq(val);
		subcount <= subcount + 1;
		estState <= CHECK;
	endrule
	
	rule endEst(estState == CHECK && !checkFlag && count == total);
		estState <= INIT;
		estDone <= True;
	endrule
	

	
	method Action put(Bit#(64) data);
		estQ.enq(data);
	endmethod
	
	method Action start;
		$display( "Starting Estimate. \n");
		estState <= CHECK;
	endmethod
	
	method Bool hasEst();
		return estDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action loadAxis(Bit#(64) inc);
		timeQ.enq(inc);
	endmethod	
		
		
endmodule: mkEstimate