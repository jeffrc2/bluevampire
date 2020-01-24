import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;
//
import Summate::*;
//
import Float32::*;
import Float64::*;


typedef enum {INIT, MULT, SUM} DotProductState deriving(Bits,Eq);

interface DotProductIfc#(numeric type vectorlen);
//INIT
	method Action put(Vector#(vectorlen,Bit#(64)) vecA, Vector#(vectorlen,Bit#(64)) vecB);
	method Action setTotal(Bit#(6) tot);
	method Action start;
//DOTPRODUCT
	method Bool hasDP();
	method Bit#(64) getDP();
	method Action clear();
endinterface


module mkDotProduct(DotProductIfc#(vectorlen));

	Clock curClk <- exposeCurrentClock;
	Reset curRst <- exposeCurrentReset;
	
	Reg#(DotProductState) dotProductState <- mkReg(INIT);
	
	SummateIfc summate <- mkSummate; 
	
	FpPairIfc#(64) mult <- mkFpMult64(clocked_by curClk, reset_by curRst);
	
	Reg#(Bit#(6)) total <- mkReg(33);
	Reg#(Bit#(6)) count <- mkReg(0);
	
	Vector#(vectorlen,Reg#(Bit#(64))) dotVecA <- replicateM(mkReg(0));
	Vector#(vectorlen,Reg#(Bit#(64))) dotVecB <- replicateM(mkReg(0));
	
	Reg#(Bool) multQueued <- mkReg(False);
	
	Reg#(Bool) dpDone <- mkReg(False);
	
	Reg#(Bit#(64)) dotProduct <- mkReg(0);
	
	rule startMult(dotProductState == MULT && count < total && !multQueued);
		//$display("Pair %u Multiplying A: %b B: %b \n", count, dotVecA[count], dotVecB[count]);
		mult.enq(dotVecA[count], dotVecB[count]);
		multQueued <= True;
	endrule
	
	rule endMult(dotProductState == MULT && count < total && multQueued);
		Bit#(64) val = mult.first;
		mult.deq;
		summate.put(val);
		multQueued <= False;
		count <= count + 1;
		//$display("Pair %u done \n", count); 
	endrule
	
	rule startSummate(dotProductState == MULT && count == total);
		//$display("Starting Summation.");
		dotProductState <= SUM;
		summate.setTotal(zeroExtend(total));
		count <= 0;
		summate.start;
	endrule
	
	rule endSummate(dotProductState ==  SUM && summate.hasSum());
		//$display("Ending Summation.");
		dpDone <= True;
		dotProductState <= INIT;
		dotProduct <= summate.getSum();
	endrule
	
	method Action start;
		//$display( "Starting Dot Product. \n");
		dotProductState <= MULT;
	endmethod
	
	method Action put(Vector#(vectorlen,Bit#(64)) vecA, Vector#(vectorlen,Bit#(64)) vecB);
		writeVReg(dotVecA, vecA); 
		writeVReg(dotVecB, vecB); 
	endmethod

	method Bool hasDP();
		return dpDone;
	endmethod
	
	method Bit#(64) getDP();
		return dotProduct;
	endmethod
	
	method Action setTotal(Bit#(6) tot);
		total <= tot;
	endmethod

	method Action clear();
		count <= 0;
		total <= 33;
		dotProductState <= INIT;
		dotProduct <= 0;
		dpDone <= False;
		multQueued <= False;
		summate.clear();
	endmethod
	
endmodule:mkDotProduct


