//
//  WalnutAudio.h
//  Walnut
//
//  A processing tap on the playback AudioQueue: it applies the radio's three-band EQ to
//  the decoded audio and measures low, mid and high levels for the animated speaker.
//

#import <AudioToolbox/AudioToolbox.h>

typedef struct WalnutTap WalnutTap;

/// Installs the tap on a newly created queue. Returns NULL if the queue refuses a tap.
WalnutTap *WalnutTapInstall(AudioQueueRef queue);
/// Removes the tap; call before disposing of the queue.
void WalnutTapRemove(WalnutTap *tap);

/// EQ gains in dB (-12…+12) for the low shelf (250 Hz), mid peak (1 kHz) and high shelf (4 kHz).
void WalnutAudioSetEQ(float lowDB, float midDB, float highDB);

/// Current band levels (RMS, roughly 0…1) after the EQ, i.e. what the listener hears.
void WalnutAudioGetLevels(float *low, float *mid, float *high);
