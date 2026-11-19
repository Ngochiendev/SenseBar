#include "../Sources/SenseBarAudioBridge/include/SenseBarAudioBridge.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdatomic.h>
#include <pthread.h>
#include <time.h>
#include <stdlib.h>

static SBAudioEqualizer *shared;
static atomic_bool done;
static void *writer(void *unused) {
    (void)unused;
    for (int i=0;i<30000;i++) {
        float bands[5]; for(int b=0;b<5;b++) bands[b]=(i+b)%25-12;
        SBAudioEqualizerPublish(shared,(float)(i%201)/100,bands,(i%3)!=0);
    }
    atomic_store(&done,true);
    return NULL;
}
static void run(SBAudioEqualizer *eq, float *src, float *dst, int n) {
    AudioBufferList in={1,{{2,(UInt32)(n*2*sizeof(float)),src}}};
    AudioBufferList out={1,{{2,(UInt32)(n*2*sizeof(float)),dst}}};
    SBAudioEqualizerRender(eq,&in,&out,2);
    for(int i=0;i<n*2;i++) assert(isfinite(dst[i]) && fabs(dst[i])<=0.98001);
}
int main(void) {
    float in[256], out[256], bands[5]={0};
    for(int i=0;i<256;i++) in[i]=0.25;
    SBAudioEqualizer *eq=SBAudioEqualizerCreate(48000,1,bands,false);
    assert(eq); run(eq,in,out,128);
    for(int i=0;i<256;i++) assert(out[i]==in[i]);
    SBAudioEqualizerPublish(eq,0,bands,false);
    for(int i=0;i<32;i++) run(eq,in,out,128);
    for(int i=0;i<256;i++) assert(out[i]==0);
    SBAudioEqualizerDestroy(eq);
    // A sine measured after settling must match the displayed cascade + headroom.
    float warm[5]={3,2,0,-1,-2}, curve[129];
    double headroom=SBAudioEqualizerCurve(48000,warm,curve,129);
    double freq=20*pow(1000,64.0/128), inputEnergy=0, outputEnergy=0;
    eq=SBAudioEqualizerCreate(48000,1,warm,true);
    for(int block=0;block<1500;block++) {
        for(int f=0;f<128;f++) { in[f*2]=0.1*sin(2*M_PI*freq*(block*128+f)/48000); in[f*2+1]=0; }
        run(eq,in,out,128);
        for(int f=0;f<128;f++) {
            assert(out[f*2+1]==0); // No left-to-right filter-history leakage.
            if(block>500) { inputEnergy+=in[f*2]*in[f*2]; outputEnergy+=out[f*2]*out[f*2]; }
        }
    }
    assert(fabs(10*log10(outputEnergy/inputEnergy)-(curve[64]+headroom))<0.03);
    SBAudioEqualizerDestroy(eq);
    // Gain-only edits must preserve the existing filter histories and phase.
    SBAudioEqualizer *reference=SBAudioEqualizerCreate(48000,1,warm,true);
    SBAudioEqualizer *adjusted=SBAudioEqualizerCreate(48000,0.5,warm,true);
    float expected[256];
    for(int block=0;block<108;block++) {
        if(block==100) SBAudioEqualizerPublish(adjusted,1,warm,true);
        for(int f=0;f<128;f++) in[f*2]=in[f*2+1]=0.1*sin(2*M_PI*60*(block*128+f)/48000);
        run(reference,in,expected,128); run(adjusted,in,out,128);
        if(block>=100) for(int f=0;f<128;f++) {
            double ramp=fmin(1,0.5+0.5*((block-100)*128+f+1)/480.0);
            assert(fabs(out[f*2]-expected[f*2]*ramp)<1e-6);
        }
    }
    SBAudioEqualizerDestroy(reference); SBAudioEqualizerDestroy(adjusted);
    // Bypass and preset changes remain sample-continuous under modest levels.
    eq=SBAudioEqualizerCreate(48000,1,warm,true);
    float previous=0;
    for(int block=0;block<400;block++) {
        if(block==100 || block==300) SBAudioEqualizerPublish(eq,1,warm,false);
        if(block==200) SBAudioEqualizerPublish(eq,1,warm,true);
        for(int f=0;f<128;f++) in[f*2]=in[f*2+1]=0.1*sin(2*M_PI*60*(block*128+f)/48000);
        run(eq,in,out,128);
        for(int f=0;f<128;f++) { assert(fabs(out[f*2]-previous)<0.004); previous=out[f*2]; }
    }
    SBAudioEqualizerDestroy(eq);
    // Gain/EQ changes, clipping and hostile input remain finite and stereo linked.
    shared=SBAudioEqualizerCreate(48000,1,NULL,false);
    pthread_t thread; pthread_create(&thread,NULL,writer,NULL);
    int blocks=0;
    do {
        for(int f=0;f<128;f++) in[f*2]=in[f*2+1]=(f%17==0 ? NAN : 4*sin(f));
        run(shared,in,out,128);
        for(int f=0;f<128;f++) assert(out[f*2]==out[f*2+1]);
        blocks++;
    } while(!atomic_load(&done));
    pthread_join(thread,NULL); SBAudioEqualizerDestroy(shared);
    for(int rate=44100;rate<=96000;rate+=((rate==44100)?3900:48000)) {
        eq=SBAudioEqualizerCreate(rate,2,warm,true);
        for(int i=0;i<256;i++) in[i]=0.2;
        for(int i=0;i<100;i++) run(eq,in,out,128);
        SBAudioEqualizerDestroy(eq);
    }
    // Hardware input precedes planar tap input; never render the microphone.
    float mic[256], left[128], right[128], lout[128], rout[128];
    for(int i=0;i<128;i++) { left[i]=0.2; right[i]=0.4; mic[i*2]=mic[i*2+1]=0.9; }
    struct { UInt32 count; AudioBuffer buffers[3]; } planarIn={3,{
        {2,sizeof(mic),mic},{1,sizeof(left),left},{1,sizeof(right),right}}};
    struct { UInt32 count; AudioBuffer buffers[2]; } planarOut={2,{
        {1,sizeof(lout),lout},{1,sizeof(rout),rout}}};
    eq=SBAudioEqualizerCreate(48000,1,NULL,false);
    SBAudioEqualizerRender(eq,(AudioBufferList *)&planarIn,(AudioBufferList *)&planarOut,2);
    for(int i=0;i<128;i++) assert(lout[i]==left[i] && rout[i]==right[i]);
    planarIn.buffers[2].mData=NULL;
    SBAudioEqualizerRender(eq,(AudioBufferList *)&planarIn,(AudioBufferList *)&planarOut,2);
    for(int i=0;i<128;i++) assert(lout[i]==0 && rout[i]==0);
    SBAudioEqualizerDestroy(eq);
    puts("PASS: unity, mute ramp, frequency response, channel isolation, hostile input, gain history, smooth bypass, 30k concurrent publications, 44.1/48/96 kHz");
    printf("Concurrent render blocks: %d\n",blocks);
    return 0;
}
