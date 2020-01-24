import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

//
import DotProduct::*;
import Summate::*;
//


typedef enum {INIT, MULT, SUM} FilterState deriving(Bits,Eq);
typedef enum {INIT, POS, NEG} MultState deriving(Bits,Eq);

interface FilterIfc#(numeric type filterlena, numeric type filterlenb);
//INIT
	method Action setCoeffVectors(Vector#(filterlena,Bit#(64)) vecA, Vector#(filterlenb,Bit#(64)) vecB);
	method Action setTotal(Bit#(20) intTot);
	method Action put(Bit#(64) data);
	method Action start;
	method ActionValue#(Bit#(64)) get;
	method Bool hasFiltered();
endinterface

//a(1)*y(n) = b(1)*x(n) + b(2)*x(n-1) + ... + b(nb+1)*x(n-nb) - a(2)*y(n-1) - ... - a(na+1)*y(n-na)

module mkFilter(FilterIfc#(filterlena, filterlenb));
	
	FIFOF#(Bit#(64)) filtQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) sumQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) subQ <- mkSizedFIFOF(200000);
	
	DotProductIfc#(2) dotProduct <- mkDotProduct;
	SummateIfc summate <- mkSummate;
	
	Reg#(FilterState) filtState <- mkReg(INIT);
	
	Reg#(MultState) multState <- mkReg(INIT);
	
	Vector#(filterlena, Reg#(Bit#(64))) filtVecA <- replicateM(mkReg(0));
	Vector#(filterlenb, Reg#(Bit#(64))) filtVecB <- replicateM(mkReg(0));
	
	Vector#(filterlenb, Reg#(Bit#(64))) filtXWindow <- replicateM(mkReg(0));
	Vector#(filterlena, Reg#(Bit#(64))) filtYWindow <- replicateM(mkReg(0));
	
	Vector#(2, Reg#(Bit#(64))) filtDotVecA <- replicateM(mkReg(0));
	Vector#(2, Reg#(Bit#(64))) filtDotVecB <- replicateM(mkReg(0));
	
	Reg#(Bit#(64)) firstX <- mkReg(0);
	
	Reg#(Bit#(20)) total <- mkReg(200000);
	Reg#(Bit#(20)) aLen <- mkReg(fromInteger(valueOf(filterlena)));
	Reg#(Bit#(20)) bLen <- mkReg(fromInteger(valueOf(filterlenb)));
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(Bit#(20)) subcount <- mkReg(0);
	Reg#(Bit#(20)) sumcount <- mkReg(0);
	Reg#(Bool) dpQueued <- mkReg(False);
	Reg#(Bool) sumQueued <- mkReg(False);
	Reg#(Bool) dpFilled <- mkReg(False);
	Reg#(Bool) filterDone <- mkReg(False);
	
	rule fillMult(filtState == MULT && count < total && !dpFilled && !dpQueued);
		//$display("Filling DP. \n");
		if (count == 0) begin
			Bit#(64) val = filtQ.first;
			filtQ.deq;
			Bit#(64) coeff = filtVecB[count];
			//$display( "First Count Pair Binary Value: %b %b \n", val, coeff);
			firstX <= val;
			filtDotVecA[0] <= val;
			filtDotVecB[0] <= coeff;
		end else begin
			if (subcount == 0) begin
				Bit#(64) spare = filtQ.first;
				filtQ.deq;
				Vector#(filterlenb, Bit#(64)) shifted = shiftInAt0(readVReg(filtXWindow), spare);
				writeVReg(filtXWindow, shifted);
			end
			if (subcount == 0 && count < bLen) begin
				
				Bit#(64) val = filtVecB[count];
				Bit#(64) coeff = firstX;
				//$display( "First Subcount Binary Value: %b %b \n", val, coeff);
				filtDotVecA[0] <= val;
				filtDotVecB[0] <= coeff;

				//result[i] += (b[i] * x[j]);
			end else if (subcount > 0 && subcount <= count) begin
				Bit#(20) diffcount = count - subcount;
				if (diffcount < bLen) begin
					Bit#(64) val = filtVecB[diffcount];
					Bit#(64) coeff = filtXWindow[diffcount];
					filtDotVecA[0] <= val;
					filtDotVecB[0] <= coeff;
					//result[i] += b[k] * x[j];
					//$display( "Moving B Window Binary Value: %b %b \n", val, coeff);
				end
				if (subcount < aLen) begin
					Bit#(64) sub = filtVecA[subcount];
					Bit#(64) coeff = {~sub[63], sub[62:0]};
					Bit#(64) val = filtYWindow[diffcount];
					//$display( "Stationary A Window Binary Value: %b %b \n", val, coeff);
					filtDotVecA[1] <= coeff;
					filtDotVecB[1] <= val;

					//result[i] -= a[j] * result[k];
				end
			end
		end
		dpFilled <= True;
	
	endrule
	
	rule startMult(filtState == MULT && count < total && dpFilled && !dpQueued);
		Vector#(2, Bit#(64)) coeff = readVReg(filtDotVecA);
		Vector#(2, Bit#(64)) val = readVReg(filtDotVecB);
		dotProduct.put(coeff,val);
		dotProduct.start;
		dpQueued <= True;
		dpFilled <= False;
		//$display("Starting DP. \n");
	endrule
	
	rule endMult(filtState == MULT && count < total && dpQueued && dotProduct.hasDP());
		//$display("Ending DP. \n");
		Bit#(64) val = dotProduct.getDP();
		dotProduct.clear();
		summate.put(val);
		dpQueued <= False;
		sumcount <= sumcount + 1;
		Vector#(2, Bit#(64)) zeroes = replicate(0);
		writeVReg(filtDotVecA, zeroes);
		writeVReg(filtDotVecB, zeroes);
		if (subcount <= count && count != 0) begin
			subcount <= subcount + 1;
		end else begin
			filtState <= SUM;
			subcount <= 0;
		end
	endrule
	
	rule startSum(filtState == SUM && !sumQueued);
		//$display("Starting Sum.\n");
		summate.start;
		summate.setTotal(sumcount);
		sumcount <= 0;
		sumQueued <= True;
	endrule
	
	rule endSum(filtState == SUM && sumQueued && summate.hasSum());
		Bit#(64) val = summate.getSum();
		if (count < 100) begin
			$display( "Filtered Value: %u %b \n", count, val);
		end
		outQ.enq(val);
		if (count < aLen) begin
			filtYWindow[count] <= val;
		end
		filtState <= MULT;
		count <= count + 1;
		summate.clear();
		sumQueued <= False;
	endrule
	
	rule endFilt(filtState == MULT && count == total && !dpFilled);
		filtState <= INIT;
		filterDone <= True;
	endrule
	
	
	method Action setCoeffVectors(Vector#(filterlena,Bit#(64)) vecA, Vector#(filterlenb,Bit#(64)) vecB);
		writeVReg(filtVecA, vecA); 
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
		filtState <= MULT;
	endmethod
	
	method Bool hasFiltered();
		return filterDone;
	endmethod
	
	
endmodule

