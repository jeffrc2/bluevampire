import BRAM::*;
import Clocks::*;
import FIFOF::*;
import RotorSpeedEstimate::*;

import "BDPI" function Bool has_data;
import "BDPI" function Action advance_in;
import "BDPI" function Bit#(64) read_input;
import "BDPI" function Action advance_sgolay;
import "BDPI" function Bit#(64) read_sgolay;

import "BDPI" function Action advance_axis;
import "BDPI" function Bit#(64) read_axis;


typedef enum {INIT, LOAD_DATA, ROTORSPEEDESTIMATE, SAMPLEINTERPOLATE, PROCESSACCELERATE, PROCESSDIRECTSIGNAL, CORRECTSIGNAL, PROCESSESTSIGNAL} State deriving(Bits,Eq);

typedef enum {READREQ, READRECV, WRITEREQ, WRITERECV} BRAMState deriving(Bits,Eq);

module mkTop (Empty);
		RotorSpeedEstimateIfc rotorSpeedEstimate <- mkRotorSpeedEstimate;
		
		Reg#(State) topState <- mkReg(INIT);
		
		Reg#(Bit#(32)) cycles <- mkReg(0);
		
		FIFOF#(Bit#(64)) inputQ <- mkSizedFIFOF(200000);
		
		rule inccycle;
                cycles <= cycles + 1;
        endrule
		
		Reg#(Bit#(20)) count <- mkReg(0);
        Reg#(Maybe#(Bit#(32))) startCycle <- mkReg(tagged Invalid);
		
		rule init_load(count < 200000 && topState == INIT);
			if (count < 1089) begin
				Bit#(64) val = read_sgolay;
				rotorSpeedEstimate.loadSgolay(val);
				advance_sgolay;
			end
			Bit#(64) inc = read_axis;
			rotorSpeedEstimate.loadAxis(inc);
			count <= count + 1;
			advance_axis;
		endrule
		
		rule start_load(count == (200000) && topState == INIT);
			count <= 0;
			topState <= LOAD_DATA;	
		endrule
		
		rule load_data(count < 800000 && topState == LOAD_DATA);
			if ( has_data ) begin
				if ( !isValid(startCycle) ) begin
                    startCycle <= tagged Valid cycles;
                end
				Bit#(64) val = read_input;
				//$display( "Entry %d \n", count);
				//$display( "Top Binary value: %b \n", val);
				if (count % 4 == 3) begin 
					inputQ.enq(val);
					rotorSpeedEstimate.put(val);
				end
				count <= count + 1;
				advance_in;
			end
		endrule
		
		//rule stop(cycles == 4294967295);
		rule stop(cycles == 36000000);
			$finish(1);
		endrule
		
		rule start_rotorSpeedEstimate(count == 800000 && topState == LOAD_DATA);
			rotorSpeedEstimate.start;
			topState <= ROTORSPEEDESTIMATE;
		endrule
		
		//Reg#(Bool) sgolayWeightDone <- mkReg(False);
		
		//rule relaySgolayWeights( !weightDone);
		//	Bit#(64) weight = get_weight;
		//	if (weight = ) begin 
		//		let d = read_weights();
		//		filter.setWeight(x,y,d);
		//		weight_advance;
		//endrule
endmodule

