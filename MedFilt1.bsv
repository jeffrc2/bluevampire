import Clocks::*;
import Connectable::*;
import FIFOF::*;
import FIFO::*;
import Vector::*;

interface MedFilt1Ifc;
//INIT
	method Action put(Bit#(64) data);
	method Action setTotal(Bit#(20) tot);
	method Action start;
//SUMMATE
	method Bool hasSum;
	method Bit#(64) getSum;
	method Action clear();
endinterface

typedef enum {INIT, CHECK, PROCESS, DIV} EstimateState deriving(Bits,Eq);

module mkSgolayFilt(SgolayFiltIfc);

	Vector#(33, Reg#(Bit#(64))) sgolaySetOn <- replicateM(mkReg(0));
//Apply a one dimensional median filter with a window size of n to the data x, which must be real, double and full.
//For n = 2m+1, y(i) is the median of x(i-m:i+m).
//For n = 2m, y(i) is the median of x(i-m:i+m-1). 
//n = 4



endmodule:mkSgolayFilt