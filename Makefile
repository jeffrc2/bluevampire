BSCFLAGS = -show-schedule -aggressive-conditions --wait-for-license 
BSCFLAGS_BSIM = -bdir ./bsim/obj -simdir ./bsim/obj -info-dir ./bsim -fdir ./bsim -D BSIM
BSVPATH=bluelib/src/
CPPFILES=bdpi.cpp

all:
	mkdir -p bsim
	mkdir -p bsim/obj
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) -p +RTS -K14M -RTS +:$(BSVPATH)  -sim -u -g mkTop Top.bsv  
	bsc $(BSCFLAGS) $(BSCFLAGS_BSIM) -sim -e mkTop -o bsim/obj/bsim bsim/obj/*.ba $(CPPFILES)

