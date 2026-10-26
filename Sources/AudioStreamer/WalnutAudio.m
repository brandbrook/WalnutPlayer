//
//  WalnutAudio.m
//  Walnut
//

#import "WalnutAudio.h"
#import <math.h>
#import <stdatomic.h>

/// One second-order filter section (RBJ audio EQ cookbook), transposed direct form II.
typedef struct { float b0, b1, b2, a1, a2; } Coeffs;
typedef struct { float z1, z2; } State;

static inline float run(const Coeffs *c, State *s, float x) {
  float y = c->b0 * x + s->z1;
  s->z1 = c->b1 * x - c->a1 * y + s->z2;
  s->z2 = c->b2 * x - c->a2 * y;
  return y;
}

typedef enum { LowShelf, Peak, HighShelf, LowPass, BandPass, HighPass } Kind;

static Coeffs design(Kind kind, double rate, double f, double q, double gainDB) {
  double A = pow(10, gainDB / 40), w = 2 * M_PI * f / rate, cw = cos(w), sw = sin(w);
  double alpha = sw / (2 * q), b0, b1, b2, a0, a1, a2;
  switch (kind) {
    case LowShelf: {
      double s = 2 * sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - s);
      a0 = (A + 1) + (A - 1) * cw + s;      a1 = -2 * ((A - 1) + (A + 1) * cw);     a2 = (A + 1) + (A - 1) * cw - s;
      break;
    }
    case HighShelf: {
      double s = 2 * sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - s);
      a0 = (A + 1) - (A - 1) * cw + s;       a1 = 2 * ((A - 1) - (A + 1) * cw);       a2 = (A + 1) - (A - 1) * cw - s;
      break;
    }
    case Peak:
      b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A; a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A;
      break;
    case LowPass:
      b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2; a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
    case HighPass:
      b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2; a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
    case BandPass:
      b0 = alpha; b1 = 0; b2 = -alpha; a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha;
      break;
  }
  return (Coeffs){ (float)(b0 / a0), (float)(b1 / a0), (float)(b2 / a0), (float)(a1 / a0), (float)(a2 / a0) };
}

// EQ settings shared with the UI; the tap redesigns its filters when the version changes.
static _Atomic float gLow = 0, gMid = 0, gHigh = 0;
static _Atomic unsigned gVersion = 1;
// Band levels published to the UI.
static _Atomic float lLow = 0, lMid = 0, lHigh = 0;

void WalnutAudioSetEQ(float lowDB, float midDB, float highDB) {
  atomic_store(&gLow, lowDB); atomic_store(&gMid, midDB); atomic_store(&gHigh, highDB);
  atomic_fetch_add(&gVersion, 1);
}

void WalnutAudioGetLevels(float *low, float *mid, float *high) {
  *low = atomic_load(&lLow); *mid = atomic_load(&lMid); *high = atomic_load(&lHigh);
}

#define MAX_CH 2

struct WalnutTap {
  AudioQueueRef queue;
  AudioQueueProcessingTapRef tap;
  AudioStreamBasicDescription format;
  unsigned version;
  Coeffs eq[3];                 // low shelf, mid peak, high shelf
  Coeffs meter[3];              // low pass, band pass, high pass for measuring
  State eqState[MAX_CH][3];
  State meterState[MAX_CH][3];
};

static void redesign(WalnutTap *t) {
  double rate = t->format.mSampleRate > 0 ? t->format.mSampleRate : 44100;
  t->eq[0] = design(LowShelf, rate, 250, 0.707, atomic_load(&gLow));
  t->eq[1] = design(Peak, rate, 1000, 0.8, atomic_load(&gMid));
  t->eq[2] = design(HighShelf, rate, 4000, 0.707, atomic_load(&gHigh));
  t->version = atomic_load(&gVersion);
}

static void tapCallback(void *client, AudioQueueProcessingTapRef aqTap, UInt32 frames, AudioTimeStamp *ts,
                        AudioQueueProcessingTapFlags *flags, UInt32 *outFrames, AudioBufferList *data) {
  WalnutTap *t = client;
  OSStatus err = AudioQueueProcessingTapGetSourceAudio(aqTap, frames, ts, flags, outFrames, data);
  if (err != noErr || *outFrames == 0) return;
  if (t->version != atomic_load(&gVersion)) redesign(t);

  // The tap's processing format is Float32; channels may be interleaved in one buffer or split.
  BOOL interleaved = !(t->format.mFormatFlags & kAudioFormatFlagIsNonInterleaved);
  UInt32 channels = MIN(t->format.mChannelsPerFrame, MAX_CH);
  double sum[3] = {0, 0, 0};
  UInt32 n = *outFrames, counted = 0;

  for (UInt32 ch = 0; ch < channels; ch++) {
    float *buf; UInt32 stride;
    if (interleaved) { buf = (float *)data->mBuffers[0].mData + ch; stride = t->format.mChannelsPerFrame; }
    else { if (ch >= data->mNumberBuffers) break; buf = data->mBuffers[ch].mData; stride = 1; }
    for (UInt32 i = 0; i < n; i++) {
      float x = buf[i * stride];
      x = run(&t->eq[0], &t->eqState[ch][0], x);
      x = run(&t->eq[1], &t->eqState[ch][1], x);
      x = run(&t->eq[2], &t->eqState[ch][2], x);
      buf[i * stride] = x;
      float lo = run(&t->meter[0], &t->meterState[ch][0], x);
      float mi = run(&t->meter[1], &t->meterState[ch][1], x);
      float hi = run(&t->meter[2], &t->meterState[ch][2], x);
      sum[0] += lo * lo; sum[1] += mi * mi; sum[2] += hi * hi;
    }
    counted += n;
  }
  if (counted == 0) return;
  atomic_store(&lLow, (float)sqrt(sum[0] / counted));
  atomic_store(&lMid, (float)sqrt(sum[1] / counted));
  atomic_store(&lHigh, (float)sqrt(sum[2] / counted));
}

WalnutTap *WalnutTapInstall(AudioQueueRef queue) {
  WalnutTap *t = calloc(1, sizeof(WalnutTap));
  t->queue = queue;
  UInt32 maxFrames = 0;
  OSStatus err = AudioQueueProcessingTapNew(queue, tapCallback, t, kAudioQueueProcessingTap_PreEffects,
                                            &maxFrames, &t->format, &t->tap);
  if (err != noErr) { free(t); return NULL; }
  double rate = t->format.mSampleRate > 0 ? t->format.mSampleRate : 44100;
  t->meter[0] = design(LowPass, rate, 250, 0.707, 0);
  t->meter[1] = design(BandPass, rate, 700, 0.7, 0);
  t->meter[2] = design(HighPass, rate, 2000, 0.707, 0);
  redesign(t);
  return t;
}

void WalnutTapRemove(WalnutTap *t) {
  if (!t) return;
  AudioQueueProcessingTapDispose(t->tap);
  free(t);
  atomic_store(&lLow, 0); atomic_store(&lMid, 0); atomic_store(&lHigh, 0);
}
