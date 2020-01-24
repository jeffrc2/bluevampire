import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;
//
import DotProduct::*;
import Filter::*;
//

typedef 1 FilterALen;
typedef 33 FilterBLen;

typedef enum {INIT, TRANSIENT_ON,TRANSIENT_OFF,FILTER,CONCAT} SgolayState deriving(Bits,Eq);

interface SgolayFiltIfc;
//INIT
	method Action loadSgolay(Bit#(64) weight);
	method Action setTotal(Bit#(20) intTot);
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasSgolay();
	method ActionValue#(Bit#(64)) get;
endinterface

module mkSgolayFilt(SgolayFiltIfc);

	DotProductIfc#(FilterBLen) dotProduct <- mkDotProduct;

	Reg#(SgolayState) sgolayState <- mkReg(INIT);

	FilterIfc#(FilterALen, FilterBLen) filter <- mkFilter;
	
	FIFOF#(Bit#(64)) sgolayQ <- mkSizedFIFOF(200000);
	FIFOF#(Bit#(64)) transOnQ <- mkSizedFIFOF(33);
	FIFOF#(Bit#(64)) transOffQ <- mkSizedFIFOF(33);
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(200000);
	
	Vector#(33, Vector#(33, Reg#(Bit#(64)))) sgolayWt <- replicateM(replicateM(mkReg(0)));
	Vector#(33, Reg#(Bit#(64))) sgolaySetOn <- replicateM(mkReg(0));
	Vector#(33, Reg#(Bit#(64))) sgolaySetOff <- replicateM(mkReg(0));
	Reg#(Bit#(20)) bitTotal <- mkReg(200000);
	Reg#(Bit#(20)) frameLen <- mkReg(33);
	Reg#(Bit#(20)) count <- mkReg(0);
	Reg#(Bit#(20)) transLen <- mkReg(16);
	
	Reg#(Bool) dotProductQueued <- mkReg(False);
	Reg#(Bool) filterQueued <- mkReg(False);
	Reg#(Bool) sgolayDone <- mkReg(False);
	
	rule startTransientOn(sgolayState == TRANSIENT_ON && !dotProductQueued); //
		if (count < transLen) begin
			Vector#(33, Bit#(64)) coeff = readVReg(sgolayWt[frameLen - 1 - count]);
			Vector#(33, Bit#(64)) val = readVReg(sgolaySetOn);
			dotProduct.put(coeff,val);
			dotProduct.start;
			dotProductQueued <= True;
		end
		if (count == transLen) begin
			$display("Transient On Complete. \n");
			sgolayState <= TRANSIENT_OFF;
			count <= 0;
		end
	endrule
	
	rule endTransientOn(sgolayState == TRANSIENT_ON && dotProductQueued && dotProduct.hasDP()); //
		Bit#(64) val = dotProduct.getDP();
		transOnQ.enq(val);
		//$display("Transient_On %u Processed: %b \n", unpack(count), val);
		dotProductQueued <= False;
		count <= count + 1;
		dotProduct.clear();
	endrule
	
	rule startTransientOff(sgolayState == TRANSIENT_OFF && !dotProductQueued); //
		if (count < transLen) begin
			Vector#(33, Bit#(64)) coeff = readVReg(sgolayWt[transLen - 1 - count]);
			Vector#(33, Bit#(64)) val = readVReg(sgolaySetOff);
			dotProduct.put(coeff,val);
			dotProduct.start;
			dotProductQueued <= True;
		end
		if (count == transLen) begin
			$display("Transient Off Complete. \n");
			sgolayState <= FILTER;
			Vector#(FilterALen, Bit#(64)) vecA = replicate('b0011111111110000000000000000000000000000000000000000000000000000);
			Vector#(FilterBLen, Bit#(64)) vecB = readVReg(sgolayWt[transLen]);
			filter.setCoeffVectors(vecA, vecB);
			count <= 0;
		end
	endrule
	
	rule endTransientOff(sgolayState == TRANSIENT_OFF && dotProductQueued && dotProduct.hasDP()); //
		Bit#(64) val = dotProduct.getDP();
		transOffQ.enq(val);
		//$display("Transient_Off %u Processed: %b \n", unpack(count), val);
		dotProductQueued <= False;
		count <= count + 1;
		dotProduct.clear();
	endrule
	
	rule filterRelay(sgolayState == FILTER && count < bitTotal && !filterQueued);
		Bit#(64) val = sgolayQ.first;
		sgolayQ.deq;
		filter.put(val);
		count <= count + 1;
	endrule
	
	rule startFilter(sgolayState == FILTER && count == bitTotal);
		$display("Filter Started. \n");
		count <= 0;
		filter.start;
		filterQueued <= True;
	endrule
	
	rule endFilter(sgolayState == FILTER && filterQueued && filter.hasFiltered());
		$display("Filter done");
		sgolayState <= CONCAT;
	endrule
	
	rule concatRelay(sgolayState == CONCAT && count < bitTotal);
		Bit#(64) temp <- filter.get();
		if (count < transLen) begin
			Bit#(64) val = transOnQ.first;
			transOnQ.deq;
			outQ.enq(val);
		end else if (count > bitTotal - transLen) begin
			Bit#(64) val = transOffQ.first;
			transOffQ.deq;
			outQ.enq(val);
		end else begin
			Bit#(64) val = temp;
			outQ.enq(val);
		end
	endrule
	
	method Action setTotal(Bit#(20) intTot);
		bitTotal <= intTot;	
	endmethod
	
	method Action put(Bit#(64) data);
		sgolayQ.enq(data);
		if (count < frameLen) begin
			let new_pos = frameLen - count - 1;
			//$display("Transient On Queue Position: %u Vector Position %u : %b ", unpack(count), unpack(new_pos), data);
			sgolaySetOn[new_pos] <= data;
		end else if (count >= (bitTotal - frameLen)) begin
			let new_pos = bitTotal - count-1;
			//$display("Transient Off Queue Position: %u Vector Position %u : %b ", unpack(count), unpack(new_pos), data);
			sgolaySetOff[new_pos] <= data; 
		end
		count <= count + 1;
	endmethod
	
	
	method Action start;
		$display( "Starting Sgolay Filter. \n");
		sgolayState <= TRANSIENT_ON;
		count <= 0;
	endmethod
	
	method Action loadSgolay(Bit#(64) weight);
		//$display("Load Position: %u Vector Position %u %u: %b ", unpack(count), unpack(count%33), unpack(count/33), weight);
		sgolayWt[count%33][count/33] <= weight;
		if (count == 1088) begin
			count <= 0;
		end else begin
			count <= count + 1;
		end
	endmethod
	
	method Bool hasSgolay();
		return sgolayDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod

endmodule:mkSgolayFilt