#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>

#include <mutex>

#include <cmath>

static size_t sgolaysize = 33*33;
static size_t readsize = 4*200000; // 8 images
static size_t timesize = 30001;
static size_t axissize = 200000;

class BdpiState{
public:
	static BdpiState* getInstance();
	BdpiState();

	

	bool hasData() { return buffersize - 1 >= (readoffset); };
	void advance(size_t inc) {
		//printf("Advancing \n");
		readoffset += inc; 
	};

	double* data1() {
		return inbuffer+readoffset; 
	};
	
	void sgolayadvance(size_t inc) {
		sgolayoffset += inc;
	}
	double* sgolay1() {
		return sgolaybuffer + sgolayoffset;
	}
	
	void axisadvance(size_t inc) {
		axisoffset += inc;
	}
	double* axis1() {
		return axisbuffer + axisoffset;
	}
	
	void timeadvance(size_t inc) {
		timeoffset += inc;
	}
	double* time1() {
		return timebuffer + timeoffset;
	}
	
	size_t offset(){
		return readoffset;
	}
	//bool setData(uint64_t data, uint64_t bytes);

private:
	static BdpiState* spInstance;

//sgolay
	double* sgolaybuffer = NULL;
	size_t sgolayoffset = 0;
	size_t sgolaybuffersize = 0;

//axis
	double* axisbuffer = NULL;
	size_t axisoffset = 0;
	size_t axisbuffersize = 0;
//time
	double* timebuffer = NULL;
	size_t timeoffset = 0;
	size_t timebuffersize = 0;

//load_data
	double* inbuffer = NULL;
	size_t readoffset = 0;
	size_t buffersize = 0;


	
	std::mutex mutex;

};

BdpiState::BdpiState() {
	
	FILE* sgolay_fin = fopen("sgolay.bin", "rb");
	sgolaybuffer = (double*)malloc(sizeof(double)*sgolaysize);
	size_t sgolay_r = fread(sgolaybuffer, sizeof(double), sgolaysize, sgolay_fin);
	sgolaybuffersize = sgolay_r;
	printf( "Simulator read %ld entries of 1,089 Sgolay weights \n", sgolaybuffersize );
	
	FILE* axis_fin = fopen("00_axis_time.bin", "rb");
	axisbuffer = (double*)malloc(sizeof(double)* readsize/4);
	size_t axis_r = fread(axisbuffer, sizeof(double), axissize, axis_fin);
	axisbuffersize = axis_r;
	printf( "Simulator read %ld entries of 200,000 Axis points \n", axisbuffersize );
	
	FILE* time_fin = fopen("01_even_time.bin", "rb");
	timebuffer = (double*)malloc(sizeof(double)* readsize/4);
	size_t time_r = fread(timebuffer, sizeof(double), timesize, time_fin);
	timebuffersize = time_r;
	printf( "Simulator read %ld entries of 30,001 Time points \n", timebuffersize );
	
	FILE* fin = fopen("00_data.bin", "rb");
	fseek(fin , 0 , SEEK_END);
	long lSize = ftell (fin);
	rewind (fin);
	inbuffer = (double*)malloc(sizeof(double)* readsize);
	size_t r = fread(inbuffer, sizeof(double), readsize, fin);
	buffersize = r;
	printf( "Simulator read %ld entries of test intput\n", buffersize );
	printf( "Simulator read %ld bytes of file\n", lSize );
}


BdpiState*
BdpiState::spInstance = NULL;
BdpiState*
BdpiState::getInstance() {
	if ( spInstance == NULL ) {
		spInstance = new BdpiState();
	}
	return spInstance;
}


void printBits(size_t const size, void const * const ptr)
{
	printf("SW Binary value: ");
    unsigned char *b = (unsigned char*) ptr;
    unsigned char byte;
    int i, j;

    for (i=size-1;i>=0;i--)
    {
        for (j=7;j>=0;j--)
        {
            byte = (b[i] >> j) & 1;
            printf("%u", byte);
        }
    }
    puts("");
}



extern "C" void advance_sgolay() {
	BdpiState* bdpi = BdpiState::getInstance();
	bdpi->sgolayadvance(1);
	//bdpi->advance(4);
}

extern "C" uint64_t read_sgolay() {
	BdpiState* bdpi = BdpiState::getInstance();
	uint64_t value = *(uint64_t*)bdpi->sgolay1();
	return value;
}

extern "C" void advance_time() {
	BdpiState* bdpi = BdpiState::getInstance();
	bdpi->timeadvance(1);
	//bdpi->advance(4);
}


extern "C" uint64_t read_time() {
	BdpiState* bdpi = BdpiState::getInstance();
	uint64_t value = *(uint64_t*)bdpi->time1();
	return value;
}



extern "C" void advance_axis() {
	BdpiState* bdpi = BdpiState::getInstance();
	bdpi->axisadvance(1);
	//bdpi->advance(4);
}

extern "C" uint64_t read_axis() {
	BdpiState* bdpi = BdpiState::getInstance();
	uint64_t value = *(uint64_t*)bdpi->axis1();
	return value;
}

extern "C" void advance_in() {
	BdpiState* bdpi = BdpiState::getInstance();
	bdpi->advance(1);
	//bdpi->advance(4);
}
extern "C" bool has_data() {
	BdpiState* bdpi = BdpiState::getInstance();
	//printf("Valid? %s \n", bdpi->hasData() ? "true" : "false");
	if ( bdpi->hasData() ) {
		return true;
	}
	return false;
}
extern "C" uint64_t read_input() {
	//printf("Reading input...\n");
	BdpiState* bdpi = BdpiState::getInstance();
	//double value = *bdpi->data1();
	//printf("%f", value);
	
	//printf("Current offset: %ld \n", bdpi->offset());
	uint64_t value = *(uint64_t*)bdpi->data1(); 
	//uint512_t value = *(uint512_t*)bdpi->data1(); 
	//printf("Value: %f \n", *(double*)bdpi->data1());
	//printBits(sizeof(value), &value);
	if ( bdpi->hasData() ) 
	{
		//printf("Datum %ld detected. \n", bdpi->offset());
		return value;
	}
	else {
		//printf("Datum not detected. \n");
		return 0;
	}
}

