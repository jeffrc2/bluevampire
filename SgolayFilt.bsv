import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;
//
import DotProduct::*;
import Filter::*;
//

`define SGOLAYFILT_DEBUG

typedef 1 FilterALen;
typedef 33 FilterBLen;
typedef TLog#(len) CountLen#(numeric type len);

typedef enum {INIT, TRANSIENT_ON,TRANSIENT_OFF,FILTER,CONCAT} SgolayState deriving(Bits,Eq);

interface SgolayFiltIfc#(numeric type datalen);
//INIT
	method Action loadSgolay(Bit#(64) weight);
	method Action put(Bit#(64) data);
	method Action start;
	method Bool hasSgolay();
	method ActionValue#(Bit#(64)) get;
endinterface

module mkSgolayFilt(SgolayFiltIfc#(datalen));

	DotProductIfc#(FilterBLen) dotProduct <- mkDotProduct;

	Reg#(SgolayState) sgolayState <- mkReg(INIT);

	FilterIfc#(datalen, FilterALen, FilterBLen) filter <- mkFilter;
	
	FIFOF#(Bit#(64)) sgolayQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	FIFOF#(Bit#(64)) transOnQ <- mkSizedFIFOF(fromInteger(valueOf(FilterBLen)));
	FIFOF#(Bit#(64)) transOffQ <- mkSizedFIFOF(fromInteger(valueOf(FilterBLen)));
	
	FIFOF#(Bit#(64)) outQ <- mkSizedFIFOF(fromInteger(valueOf(datalen)));
	
	Vector#(FilterBLen, Vector#(FilterBLen, Reg#(Bit#(64)))) sgolayWt <- replicateM(replicateM(mkReg(0)));
	Vector#(FilterBLen, Reg#(Bit#(64))) sgolaySetOn <- replicateM(mkReg(0));
	Vector#(FilterBLen, Reg#(Bit#(64))) sgolaySetOff <- replicateM(mkReg(0));
	Reg#(Bit#(CountLen#(datalen))) bitTotal <- mkReg(fromInteger(valueOf(datalen)));
	//Reg#(Bit#(CountLen#(datalen))) frameLen <- mkReg(fromInteger(valueOf(FilterBLen)));
	Reg#(Bit#(CountLen#(datalen))) count <- mkReg(0);
	//Reg#(Bit#(CountLen#(datalen))) transLen <- mkReg(fromInteger(valueOf(FilterBLen))/2);
	
	Reg#(Bool) dotProductQueued <- mkReg(False);
	Reg#(Bool) filterQueued <- mkReg(False);
	Reg#(Bool) sgolayDone <- mkReg(False);
	
	rule startTransientOn(sgolayState == TRANSIENT_ON && !dotProductQueued); //
		if (count < fromInteger(valueOf(FilterBLen))/2) begin
			Vector#(FilterBLen, Bit#(64)) coeff = readVReg(sgolayWt[fromInteger(valueOf(FilterBLen)) - 1 - count]);
			Vector#(FilterBLen, Bit#(64)) val = readVReg(sgolaySetOn);
			dotProduct.put(coeff,val);
			dotProduct.start;
			dotProductQueued <= True;
		end
		if (count == fromInteger(valueOf(FilterBLen))/2) begin
			sgolayState <= TRANSIENT_OFF;
			count <= 0;
`ifdef SGOLAYFILT_DEBUG_DEBUG
			$display("Transient On Complete. \n");
`endif
		end
	endrule
	
	rule endTransientOn(sgolayState == TRANSIENT_ON && dotProductQueued && dotProduct.hasDP()); //
		Bit#(64) val = dotProduct.getDP();
		transOnQ.enq(val);
		dotProductQueued <= False;
		count <= count + 1;
		dotProduct.clear();
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display("Transient_On %u Processed: %b \n", unpack(count), val);
`endif
	endrule
	
	rule startTransientOff(sgolayState == TRANSIENT_OFF && !dotProductQueued); //
		if (count < fromInteger(valueOf(FilterBLen))/2) begin
			Vector#(FilterBLen, Bit#(64)) coeff = readVReg(sgolayWt[fromInteger(valueOf(FilterBLen))/2 - 1 - count]);
			Vector#(FilterBLen, Bit#(64)) val = readVReg(sgolaySetOff);
			dotProduct.put(coeff,val);
			dotProduct.start;
			dotProductQueued <= True;
		end
		if (count == fromInteger(valueOf(FilterBLen))/2) begin
			$display("Transient Off Complete. \n");
			sgolayState <= FILTER;
			Vector#(FilterALen, Bit#(64)) vecA = replicate('b0011111111110000000000000000000000000000000000000000000000000000);
			Vector#(FilterBLen, Bit#(64)) vecB = readVReg(sgolayWt[fromInteger(valueOf(FilterBLen))/2]);
			filter.setCoeffVectors(vecA, vecB);
			count <= 0;
`ifdef SGOLAYFILT_DEBUG_DEBUG
			$display("Transient Off Complete. \n");
`endif
		end
	endrule
	
	rule endTransientOff(sgolayState == TRANSIENT_OFF && dotProductQueued && dotProduct.hasDP()); //
		Bit#(64) val = dotProduct.getDP();
		transOffQ.enq(val);
		dotProductQueued <= False;
		count <= count + 1;
		dotProduct.clear();
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display("Transient_Off %u Processed: %b \n", unpack(count), val);
`endif
	endrule
	
	rule filterRelay(sgolayState == FILTER && count < fromInteger(valueOf(datalen)) && !filterQueued);
		Bit#(64) val = sgolayQ.first;
		sgolayQ.deq;
		filter.put(val);
		count <= count + 1;
	endrule
	
	rule startFilter(sgolayState == FILTER && count == fromInteger(valueOf(datalen)));
		count <= 0;
		filter.start;
		filterQueued <= True;
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display("Filter started.");
`endif
	endrule
	
	rule endFilter(sgolayState == FILTER && filterQueued && filter.hasFiltered());
		sgolayState <= CONCAT;
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display("Filter done.");
`endif
	endrule
	
	rule concatRelay(sgolayState == CONCAT && count < fromInteger(valueOf(datalen)));
		Bit#(64) temp <- filter.get();
		if (count < fromInteger(valueOf(FilterBLen))/2) begin
			Bit#(64) val = transOnQ.first;
			transOnQ.deq;
			outQ.enq(val);
		end else if (count > fromInteger(valueOf(datalen)) - (fromInteger(valueOf(FilterBLen))/2)) begin
			Bit#(64) val = transOffQ.first;
			transOffQ.deq;
			outQ.enq(val);
		end else begin
			Bit#(64) val = temp;
			outQ.enq(val);
		end
		count <= count + 1;
	endrule
	
	rule endConcat(sgolayState == CONCAT && count == fromInteger(valueOf(datalen)));
		sgolayDone <= True;
		sgolayState <= INIT;
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display( "Sgolay Filter Complete. \n");
`endif
	endrule
	
	method Action put(Bit#(64) data);
		sgolayQ.enq(data);
		if (count < fromInteger(valueOf(FilterBLen))) begin
			let new_pos = fromInteger(valueOf(FilterBLen)) - count - 1;
			sgolaySetOn[new_pos] <= data;
`ifdef SGOLAYFILT_DEBUG_DEBUG
			$display("Transient On Queue Position: %u Vector Position %u : %b ", unpack(count), unpack(new_pos), data);
`endif
		end else if (count >= (fromInteger(valueOf(datalen)) - fromInteger(valueOf(FilterBLen)))) begin
			let new_pos = fromInteger(valueOf(datalen)) - count-1;
			sgolaySetOff[new_pos] <= data; 
`ifdef SGOLAYFILT_DEBUG_DEBUG
			$display("Transient Off Queue Position: %u Vector Position %u : %b ", unpack(count), unpack(new_pos), data);
`endif
		end
		count <= count + 1;
	endmethod
	
	
	method Action start;
		sgolayState <= TRANSIENT_ON;
		count <= 0;
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display( "Starting Sgolay Filter. \n");
`endif
	endmethod
	
	method Action loadSgolay(Bit#(64) weight);
		sgolayWt[count%fromInteger(valueOf(FilterBLen))][count/fromInteger(valueOf(FilterBLen))] <= weight;
		if (count == fromInteger(valueOf(FilterBLen))*fromInteger(valueOf(FilterBLen))-1) begin
			count <= 0;
		end else begin
			count <= count + 1;
		end
`ifdef SGOLAYFILT_DEBUG_DEBUG
		$display("Load Position: %u Vector Position %u %u: %b ", unpack(count), unpack(count%fromInteger(valueOf(FilterBLen))), unpack(count/fromInteger(valueOf(FilterBLen))), weight);
`endif
	endmethod
	
	method Bool hasSgolay();
		return sgolayDone;
	endmethod
	
    method ActionValue#(Bit#(64)) get;
        outQ.deq;
        return outQ.first;
    endmethod

endmodule:mkSgolayFilt