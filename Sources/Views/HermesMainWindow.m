//
//  HermesMainWindow.m
//  Hermes
//
//  Created by Nicholas Riley on 9/10/16.
//
//

#import "HermesMainWindow.h"
#import "Walnut-Swift.h"

@implementation HermesMainWindow

// Walnut shows the radio window instead; the old main window stays hidden but keeps its
// controllers' views alive. Anything asking it to come forward brings the radio forward.
- (void)makeKeyAndOrderFront:(id)sender { [[RadioWindowController shared] bringToFront]; }
- (void)orderFront:(id)sender { [[RadioWindowController shared] bringToFront]; }
- (void)orderFrontRegardless { [[RadioWindowController shared] bringToFront]; }

- (void)sendEvent:(NSEvent *)theEvent {
  if ([theEvent type] == NSKeyDown) {

    // don't ever let space bar get through to the field editor so it can be used for play/pause
    if ([[theEvent characters] isEqualToString:@" "] && ([theEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask) == 0) {
      [[NSApp mainMenu] performKeyEquivalent:theEvent];
      return;
    }
  }
  [super sendEvent:theEvent];
}

@end
