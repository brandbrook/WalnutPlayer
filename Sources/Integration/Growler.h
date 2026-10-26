//
//  Growler.h
//  Hermes
//

#import <UserNotifications/UserNotifications.h>

@class Song;

#define GROWLER [HMSAppDelegate growler]

@interface Growler : NSObject<UNUserNotificationCenterDelegate>

- (void) growl:(Song*)song withImage:(NSData*)image isNew:(BOOL) n;

@end
