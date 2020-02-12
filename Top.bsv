import BRAM::*;
import Clocks::*;
import FIFOF::*;
import RotorSpeedEstimate::*;
import SampleInterpolate::*;

import "BDPI" function Bool has_data;
import "BDPI" function Action advance_in;
import "BDPI" function Bit#(64) read_input;
import "BDPI" function Action advance_sgolay;
import "BDPI" function Bit#(64) read_sgolay;

import "BDPI" function Action advance_axis;
import "BDPI" function Bit#(64) read_axis;

import "BDPI" function Action advance_time;
import "BDPI" function Bit#(64) read_time;

typedef 200000 DataLen;
typedef 800000 DataSize;
typedef 33 FrameLen;
typedef TLog#(DataSize) CountSize;
typedef 30001 TimeLen;

typedef enum {INIT, LOAD_DATA, ROTORSPEEDESTIMATE, SAMPLEINTERPOLATE, PROCESSACCELERATE, PROCESSDIRECTSIGNAL, CORRECTSIGNAL, PROCESSESTSIGNAL} State deriving(Bits,Eq);

typedef enum {READREQ, READRECV, WRITEREQ, WRITERECV} BRAMState deriving(Bits,Eq);

module mkTop (Empty);
		RotorSpeedEstimateIfc#(DataLen) rotorSpeedEstimate <- mkRotorSpeedEstimate;
		SampleInterpolateIfc#(DataLen, TimeLen) sampleInterpolate <- mkSampleInterpolate;
		Reg#(State) topState <- mkReg(INIT);
		
		Reg#(Bit#(32)) cycles <- mkReg(0);
		
		Reg#(Bit#(CountSize)) trimmedTotal <- mkReg(0);
		
		FIFOF#(Bit#(64)) inputQ <- mkSizedFIFOF(fromInteger(valueOf(DataLen)));
		
		rule inccycle;
                cycles <= cycles + 1;
        endrule
		
		Reg#(Bit#(CountSize)) count <- mkReg(0);
        Reg#(Maybe#(Bit#(32))) startCycle <- mkReg(tagged Invalid);
		
		rule init_load(count < fromInteger(valueOf(DataLen)) && topState == INIT);
			if (count < fromInteger(valueOf(FrameLen))*fromInteger(valueOf(FrameLen))) begin
				Bit#(64) val = read_sgolay;
				rotorSpeedEstimate.loadSgolay(val);
				advance_sgolay;
			end
			
			if (count < fromInteger(valueOf(TimeLen))) begin
				Bit#(64) t = read_time;
				sampleInterpolate.loadTime(t);
				advance_time;
			end
			
			Bit#(64) inc = read_axis;
			rotorSpeedEstimate.loadAxis(inc);
			count <= count + 1;
			advance_axis;
		endrule
		
		rule start_load(count == fromInteger(valueOf(DataLen)) && topState == INIT);
			count <= 0;
			topState <= LOAD_DATA;	
		endrule
		
		rule load_data(count < fromInteger(valueOf(DataSize)) && topState == LOAD_DATA);
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
		
		rule start_rotorSpeedEstimate(count == fromInteger(valueOf(DataSize)) && topState == LOAD_DATA);
			rotorSpeedEstimate.start;
			topState <= ROTORSPEEDESTIMATE;
			count <= 0;
		endrule
		
		rule end_rotorSpeedEstimate(topState == ROTORSPEEDESTIMATE && rotorSpeedEstimate.hasRSE);
			topState <= SAMPLEINTERPOLATE;
			trimmedTotal <= zeroExtend(rotorSpeedEstimate.getNewTotal);
		endrule
		
		rule sampleInterpolate_relay(topState == SAMPLEINTERPOLATE && count < trimmedTotal);
			Bit#(64) tval <- rotorSpeedEstimate.getTime;
			Bit#(64) sval <- rotorSpeedEstimate.getSpeed;
			sampleInterpolate.putTime(tval);
			sampleInterpolate.putSpeed(sval);
			count <= count + 1;
		endrule
		
		rule start_sampleInterpolate(count == trimmedTotal && topState == SAMPLEINTERPOLATE);
			sampleInterpolate.start;
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

