import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

//
import DotProduct::*;
import Summate::*;
//
import Float32::*;
import Float64::*;

`define FILTER_DEBUG

typedef TLog#(len) CountLen#(numeric type len);

typedef TSub#(lena, 1) VecASize#(numeric type lena);

typedef enum {INIT, DP, SUB} FilterState deriving(Bits,Eq);

interface FilterIfc#(numeric type datalen, numeric type filterlena, numeric type filterlenb);
//INIT
	method Action setCoeffVectors(Vector#(filterlena,Bit#(64)) vecA, Vector#(filterlenb,Bit#(64)) vecB);
	method Action put(Bit#(64) data);
	method Action start;
	method ActionValue#(Bit#(64)) get;
	method Bool hasFiltered();
endinterface

//a(1)*y(n) = b(1)*x(n) + b(2)*x(n-1) + ... + b(nb+1)*x(n-nb) - a(2)*y(n-1) - ... - a(na+1)*y(n-na)

module mkFilter(FilterIfc#(datalen, filterlena, filterlenb));
	
	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	FIFOF#(Bit#(64)) filtQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	FpPairIfc#(64) sub <- mkFpSub64(clocked_by curClk, reset_by curRst);
	
	DotProductIfc#(filterlena) dotProductA <- mkDotProduct;
	DotProductIfc#(filterlenb) dotProductB <- mkDotProduct;
	
	Reg#(FilterState) filtState <- mkReg(INIT);
	

	Vector#(filterlenb, Reg#(Bit#(64))) filtVecB <- replicateM(mkReg(0));
	Vector#(filterlenb, Reg#(Bit#(64))) filtVecX <- replicateM(mkReg(0));
	
	Vector#(VecASize#(filterlena), Reg#(Bit#(64))) filtVecA <- replicateM(mkReg(0));
	Vector#(VecASize#(filterlena), Reg#(Bit#(64))) filtVecY <- replicateM(mkReg(0));
	
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	Reg#(Bit#(CountLen#(datalen))) subcount <- mkReg(0);
	Reg#(Bit#(CountLen#(datalen))) sumcount <- mkReg(0);
	Reg#(Bool) dpAQueued <- mkReg(False);
	Reg#(Bool) dpBQueued <- mkReg(False);
	Reg#(Bool) sumQueued <- mkReg(False);
	Reg#(Bool) filterDone <- mkReg(False);
	
	rule startDP(filtState == DP && !dpBQueued);
		if (count < fromInteger(valueOf(datalen))) begin
			Bit#(64) val = filtQ.first;
			filtQ.deq;
			Vector#(filterlenb, Bit#(64)) vecX = shiftInAt0(readVReg(filtVecX), val);
			Vector#(filterlenb, Bit#(64)) vecB = readVReg(filtVecB);
			dotProductB.put(vecX, vecB);
			dotProductB.start;
			writeVReg(filtVecX, vecX);
			dpBQueued <= True;
			if (count > 0 && fromInteger(valueOf(datalen)) > 1) begin
				Vector#(1, Bit#(64)) space = replicate(0);
				Vector#(filterlena, Bit#(64)) vecY = append(space,readVReg(filtVecY));
				Vector#(filterlena, Bit#(64)) vecA = append(space,readVReg(filtVecA));
				dotProductA.put(vecY,vecA);
				dotProductA.start;
				dpAQueued <= True;
			end
		end else begin
			filtState <= INIT;
			filterDone <= True;
		end
	endrule
	
	rule endDP(filtState == DP && !dpAQueued && dpBQueued && dotProductB.hasDP);
	//no vector A subtraction
		Bit#(64) val = dotProductB.getDP();
		dotProductB.clear();
		outQ.enq(val);
		Vector#(VecASize#(filterlena), Bit#(64)) vecY = shiftInAt0(readVReg(filtVecY), val);
		count <= count + 1;
		dpBQueued <= False;
		writeVReg(filtVecY, vecY);
	endrule
	
	rule startSub(filtState == DP && dpAQueued && dpBQueued && dotProductA.hasDP && dotProductB.hasDP);
		Bit#(64) valA = dotProductA.getDP();
		Bit#(64) valB = dotProductB.getDP();
		dotProductA.clear();
		dotProductB.clear();
		dpBQueued <= False;
		dpAQueued <= False;
		sub.enq(valB, valA);
		filtState <= SUB;
	endrule
	
	rule endSub(filtState == SUB);
		Bit#(64) val = sub.first;
		sub.deq;
		
		outQ.enq(val);
		filtState <= DP;
		Vector#(VecASize#(filterlena), Bit#(64)) vecY = shiftInAt0(readVReg(filtVecY), val);
		
		writeVReg(filtVecY, vecY);
		count <= count + 1;
	endrule
	
	
	method Action setCoeffVectors(Vector#(filterlena,Bit#(64)) vecA, Vector#(filterlenb,Bit#(64)) vecB);
		writeVReg(filtVecA, tail(vecA)); 
		writeVReg(filtVecB, vecB); 
	endmethod
	
	method Action put(Bit#(64) data);
		filtQ.enq(data);
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod
	
	method Action start;
		$display( "Starting Filter. \n");
		filtState <= DP;
	endmethod
	
	method Bool hasFiltered();
		return filterDone;
	endmethod
	
	
endmodule

