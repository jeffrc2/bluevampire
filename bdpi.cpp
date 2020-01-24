#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>

#include <mutex>

#include <cmath>

static size_t sgolaysize = 33*33;
static size_t readsize = 4*200000; // 8 images

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

//axis_fin
	double* axisbuffer = NULL;
	size_t axisoffset = 0;
	size_t axissize = 0;
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
	sgolaysize = sgolay_r;
	printf( "Simulator read %ld entries of 1,089 Sgolay weights \n", sgolaysize );
	
	FILE* axis_fin = fopen("00_axis_time.bin", "rb");
	axisbuffer = (double*)malloc(sizeof(double)* readsize/4);
	size_t axis_r = fread(axisbuffer, sizeof(double), axissize, axis_fin);
	axissize = axis_r;
	printf( "Simulator read %ld entries of 1,089 Sgolay weights \n", sgolaysize );
	
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

