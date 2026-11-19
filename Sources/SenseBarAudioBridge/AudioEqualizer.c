#include "include/SenseBarAudioBridge.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define BANDS 5
#define CHANNELS 2
#define CHUNK 128
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio mailbox requires lock-free atomics");

typedef struct { double c[BANDS][5]; double gain, level; unsigned sections; } SBFilterConfig;
typedef struct { double x1, x2, y1, y2; } SBFilterDelay;
struct SBAudioEqualizer {
    SBFilterConfig slots[3];
    _Atomic(unsigned) middle;
    unsigned back, front;
    SBFilterConfig current, next, desired;
    SBFilterDelay delays[2][CHANNELS][BANDS];
    unsigned bank, fade, fadeLength;
    double sampleRate, reduction, volume, targetVolume;
    unsigned volumeFrames, volumeRampLength;
    SBFilterConfig published;
    float publishedBands[BANDS];
    bool publishedEnabled;
};

static SBFilterConfig makeConfig(double rate, const float *gains, bool enabled, float volume) {
    const double frequencies[BANDS] = {60, 250, 1000, 4000, 12000};
    SBFilterConfig config = {0};
    for (int b = 0; b < BANDS; b++) {
        double db = enabled && gains && isfinite(gains[b]) ? fmax(-12, fmin(12, gains[b])) : 0;
        if (fabs(db) < 0.00001) continue;
        double *c = config.c[config.sections++];
        double a = pow(10, db / 40), w = 2 * M_PI * fmin(frequencies[b], rate * 0.45) / rate;
        double cs = cos(w), sn = sin(w), alpha = sn / 2 * sqrt(2), root = 2 * sqrt(a) * alpha;
        double b0, b1, b2, a0, a1, a2;
        if (b == 0) {
            b0 = a*((a+1)-(a-1)*cs+root); b1 = 2*a*((a-1)-(a+1)*cs); b2 = a*((a+1)-(a-1)*cs-root);
            a0 = (a+1)+(a-1)*cs+root; a1 = -2*((a-1)+(a+1)*cs); a2 = (a+1)+(a-1)*cs-root;
        } else if (b == BANDS-1) {
            b0 = a*((a+1)+(a-1)*cs+root); b1 = -2*a*((a-1)+(a+1)*cs); b2 = a*((a+1)+(a-1)*cs-root);
            a0 = (a+1)-(a-1)*cs+root; a1 = 2*((a-1)-(a+1)*cs); a2 = (a+1)-(a-1)*cs-root;
        } else {
            alpha = sn / 2;
            b0 = 1+alpha*a; b1 = -2*cs; b2 = 1-alpha*a;
            a0 = 1+alpha/a; a1 = -2*cs; a2 = 1-alpha/a;
        }
        c[0]=b0/a0; c[1]=b1/a0; c[2]=b2/a0; c[3]=a1/a0; c[4]=a2/a0;
    }
    // Evaluate overlapping boosts on the control thread. Identity bands have
    // no section, so both coefficient analysis and rendering skip them.
    double peak = 1;
    for (int i=-1; config.sections && i<=513; i++) {
        double frequency = i < 0 ? 0 : i > 512 ? rate * 0.5 : 10 * pow(rate*0.049, (double)i/512);
        double w = 2*M_PI*frequency/rate;
        double cs=cos(w), sn=sin(w), cs2=cos(2*w), sn2=sin(2*w), magnitude=1;
        for (unsigned b=0; b<config.sections; b++) {
            double *c=config.c[b];
            double nr=c[0]+c[1]*cs+c[2]*cs2, ni=-c[1]*sn-c[2]*sn2;
            double dr=1+c[3]*cs+c[4]*cs2, di=-c[3]*sn-c[4]*sn2;
            magnitude *= hypot(nr,ni)/fmax(hypot(dr,di),1e-12);
        }
        peak=fmax(peak,magnitude);
    }
    config.gain = 1 / peak;
    config.level = isfinite(volume) ? fmax(0,fmin(8,volume)) : 1;
    return config;
}

static bool sameFilters(const SBFilterConfig *a, const SBFilterConfig *b) {
    return a->sections==b->sections && a->gain==b->gain
        && memcmp(a->c,b->c,sizeof(a->c))==0;
}

SBAudioEqualizer *SBAudioEqualizerCreate(double rate, float gain, const float *bands, bool enabled) {
    if (!isfinite(rate) || rate < 8000 || rate > 384000) return NULL;
    SBAudioEqualizer *eq = calloc(1, sizeof(*eq));
    if (!eq) return NULL;
    eq->sampleRate=rate; eq->back=2; eq->front=0;
    atomic_init(&eq->middle,1);
    eq->published=makeConfig(rate,bands,enabled,1);
    if (bands) memcpy(eq->publishedBands,bands,sizeof(eq->publishedBands));
    eq->publishedEnabled=enabled;
    eq->current=eq->published;
    eq->current.level = isfinite(gain) ? fmax(0,fmin(8,gain)) : 1;
    eq->desired=eq->next=eq->current;
    eq->volume=eq->targetVolume=eq->current.level;
    eq->volumeRampLength=(unsigned)(rate*0.01);
    eq->fadeLength=(unsigned)(rate*0.025); eq->reduction=1;
    return eq;
}
void SBAudioEqualizerDestroy(SBAudioEqualizer *eq) { free(eq); }

/// Single control-thread producer. Each exchange transfers exclusive ownership.
void SBAudioEqualizerPublish(SBAudioEqualizer *eq, float gain, const float *bands, bool enabled) {
    float zero[BANDS]={0};
    if (!bands) bands=zero;
    if (enabled!=eq->publishedEnabled || memcmp(bands,eq->publishedBands,sizeof(zero))!=0) {
        eq->published=makeConfig(eq->sampleRate,bands,enabled,1);
        memcpy(eq->publishedBands,bands,sizeof(zero));
        eq->publishedEnabled=enabled;
    }
    eq->slots[eq->back]=eq->published;
    eq->slots[eq->back].level = isfinite(gain) ? fmax(0,fmin(8,gain)) : 1;
    unsigned previous=atomic_exchange_explicit(&eq->middle,eq->back|4,memory_order_acq_rel);
    eq->back=previous&3;
}

/// Called only before starting HAL, when no consumer can access the state.
void SBAudioEqualizerPrepare(SBAudioEqualizer *eq, float gain, const float *bands, bool enabled) {
    SBAudioEqualizerPublish(eq,gain,bands,enabled);
    unsigned previous=atomic_exchange_explicit(&eq->middle,eq->front,memory_order_acq_rel);
    eq->front=previous&3;
    eq->current=eq->slots[eq->front];
    eq->desired=eq->next=eq->current;
    eq->volume=eq->targetVolume=eq->current.level;
    eq->volumeFrames=0;
}

static double filtered(SBAudioEqualizer *eq, unsigned bank, int channel, double x, const SBFilterConfig *cfg) {
    for (unsigned b=0;b<cfg->sections;b++) {
        const double *c=cfg->c[b]; SBFilterDelay *s=&eq->delays[bank][channel][b];
        double y=c[0]*x+c[1]*s->x1+c[2]*s->x2-c[3]*s->y1-c[4]*s->y2;
        if (!isfinite(y)) { memset(s,0,sizeof(*s)); y=0; }
        if (fabs(y)<1e-25) y=0;
        s->x2=s->x1; s->x1=x; s->y2=s->y1; s->y1=y; x=y;
    }
    return x*cfg->gain;
}

/// One HAL consumer; all histories and transitions belong exclusively to it.
void SBAudioEqualizerRender(SBAudioEqualizer *eq, const AudioBufferList *input, AudioBufferList *output, unsigned channels) {
    for (unsigned b=0;b<output->mNumberBuffers;b++) {
        AudioBuffer *o=&output->mBuffers[b]; if(o->mData) memset(o->mData,0,o->mDataByteSize);
    }
    if (!channels || channels>2) return;
    const float *source[2]={NULL,NULL}; unsigned stride=channels, frames=0;
    // The private aggregate appends tap inputs after hardware inputs. Never
    // fall back to an earlier microphone buffer when the tap has no samples.
    if (input->mNumberBuffers) {
        const AudioBuffer *b=&input->mBuffers[input->mNumberBuffers-1];
        if (b->mData && b->mNumberChannels==channels) {
            source[0]=b->mData; source[1]=channels==2 ? source[0]+1 : source[0];
            frames=b->mDataByteSize/(sizeof(float)*channels);
        }
    }
    if (!source[0] && channels==2 && input->mNumberBuffers>=2) {
        const AudioBuffer *l=&input->mBuffers[input->mNumberBuffers-2], *r=&input->mBuffers[input->mNumberBuffers-1];
        if(l->mNumberChannels==1 && r->mNumberChannels==1 && l->mData && r->mData) {
            source[0]=l->mData; source[1]=r->mData; stride=1;
            frames=fmin(l->mDataByteSize,r->mDataByteSize)/sizeof(float);
        }
    }
    if (!source[0]) return;
    for (unsigned offset=0;offset<frames;offset+=CHUNK) {
        if (atomic_load_explicit(&eq->middle,memory_order_acquire)&4) {
            unsigned previous=atomic_exchange_explicit(&eq->middle,eq->front,memory_order_acq_rel);
            eq->front=previous&3;
            eq->desired=eq->slots[eq->front];
            if(eq->targetVolume!=eq->desired.level) {
                eq->targetVolume=eq->desired.level;
                eq->volumeFrames=eq->volumeRampLength;
            }
        }
        if (!eq->fade && !sameFilters(&eq->current,&eq->desired)) {
            eq->next=eq->desired;
            memset(eq->delays[1-eq->bank],0,sizeof(eq->delays[0]));
            eq->fade=eq->fadeLength;
        }
        float scratch[CHUNK][2]; double peak=0;
        unsigned count=frames-offset<CHUNK ? frames-offset : CHUNK;
        for(unsigned f=0;f<count;f++) {
            if(eq->volumeFrames) {
                eq->volume+=(eq->targetVolume-eq->volume)/eq->volumeFrames;
                if(--eq->volumeFrames==0) eq->volume=eq->targetVolume;
            }
            double blend=eq->fade ? 1-(double)eq->fade/eq->fadeLength : 0;
            for(int c=0;c<2;c++) {
                double x=source[c][(offset+f)*stride]; if(!isfinite(x)) x=0;
                double y=filtered(eq,eq->bank,c,x,&eq->current);
                if(eq->fade) y=y*(1-blend)+filtered(eq,1-eq->bank,c,x,&eq->next)*blend;
                y*=eq->volume;
                scratch[f][c]=isfinite(y) ? y : 0; peak=fmax(peak,fabs(scratch[f][c]));
            }
            if(eq->fade && --eq->fade==0) { eq->current=eq->next; eq->bank=1-eq->bank; }
        }
        double demand=peak>0.98 ? 0.98/peak : 1;
        double release=exp(-(double)count/(eq->sampleRate*0.12));
        eq->reduction=demand<eq->reduction ? demand : demand+release*(eq->reduction-demand);
        unsigned firstChannel=0;
        for(unsigned b=0;b<output->mNumberBuffers;b++) {
            AudioBuffer *o=&output->mBuffers[b]; unsigned n=o->mNumberChannels;
            if(o->mData && n) {
                unsigned capacity=o->mDataByteSize/(sizeof(float)*n); float *dst=o->mData;
                for(unsigned f=0;f<count && offset+f<capacity;f++)
                    for(unsigned c=0;c<n && firstChannel+c<2;c++)
                        dst[(offset+f)*n+c]=(float)fmax(-0.98,fmin(0.98,scratch[f][firstChannel+c]*eq->reduction));
            }
            firstChannel+=n;
        }
    }
}

float SBAudioEqualizerCurve(double rate, const float *bands, float *response, unsigned count) {
    if (!isfinite(rate) || rate<8000 || rate>384000) {
        for(unsigned i=0;i<count;i++) response[i]=0;
        return 0;
    }
    SBFilterConfig cfg=makeConfig(rate,bands,true,1);
    double upper=fmin(20000,rate*0.49);
    for (unsigned i=0;i<count;i++) {
        double w=2*M_PI*(20*pow(upper/20,(double)i/fmax(count-1,1)))/rate, magnitude=1;
        double cs=cos(w), sn=sin(w), cs2=cos(2*w), sn2=sin(2*w);
        for(unsigned b=0;b<cfg.sections;b++) {
            double *c=cfg.c[b];
            double nr=c[0]+c[1]*cs+c[2]*cs2, ni=-c[1]*sn-c[2]*sn2;
            double dr=1+c[3]*cs+c[4]*cs2, di=-c[3]*sn-c[4]*sn2;
            magnitude*=hypot(nr,ni)/fmax(hypot(dr,di),1e-12);
        }
        response[i]=20*log10(fmax(magnitude,1e-12));
    }
    return (float)(20*log10(fmax(cfg.gain,1e-12)));
}
