/**
 * @file Growler.h
 * @brief Notification Center integration for the rest of Hermes
 *
 * Provides unified access to displaying notifications for different kinds
 * of events without having to deal with UserNotifications directly.
 */

#import "Growler.h"
#import "PreferencesController.h"
#import "PlaybackController.h"

#define CATEGORY_SONG       @"song"
#define CATEGORY_SONG_LIKED @"song-liked"

@implementation Growler

- (id) init {
  if (!(self = [super init])) return nil;

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center setDelegate:self];

  UNNotificationAction *skipAction =
    [UNNotificationAction actionWithIdentifier:@"next" title:@"Skip" options:0];
  UNNotificationAction *likeAction =
    [UNNotificationAction actionWithIdentifier:@"like" title:@"Like" options:0];
  UNNotificationAction *unlikeAction =
    [UNNotificationAction actionWithIdentifier:@"like" title:@"Remove Like" options:0];
  UNNotificationAction *dislikeAction =
    [UNNotificationAction actionWithIdentifier:@"dislike" title:@"Dislike" options:0];

  /* The like action's title depends on the song's current rating, so there is
     a category for each state */
  [center setNotificationCategories:[NSSet setWithObjects:
    [UNNotificationCategory categoryWithIdentifier:CATEGORY_SONG
                                           actions:@[skipAction, likeAction, dislikeAction]
                                 intentIdentifiers:@[]
                                           options:0],
    [UNNotificationCategory categoryWithIdentifier:CATEGORY_SONG_LIKED
                                           actions:@[skipAction, unlikeAction, dislikeAction]
                                 intentIdentifiers:@[]
                                           options:0],
    nil]];

  [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                        completionHandler:^(BOOL granted, NSError *error) {
    if (error != nil) {
      NSLog(@"Notification authorization failed: %@", error);
    }
  }];

  return self;
}

/* Notification attachments must be files, so album art is written to a
   temporary file which UserNotifications then moves into its own storage */
- (UNNotificationAttachment*) attachmentForImage:(NSData*)image {
  if (image == nil) return nil;

  NSString *name = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"jpg"];
  NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
  if (![image writeToURL:url atomically:YES]) return nil;

  NSError *error = nil;
  UNNotificationAttachment *attachment =
    [UNNotificationAttachment attachmentWithIdentifier:@"art" URL:url options:nil error:&error];
  if (attachment == nil) {
    NSLog(@"Couldn't attach album art to notification: %@", error);
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
  }
  return attachment;
}

- (void) growl:(Song*)song withImage:(NSData*)image isNew:(BOOL)n {
  // Unconditionally remove all notifications from notification center to behave like iTunes
  // notifications and does not fill the notification center with old song details.
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center removeAllDeliveredNotifications];

  if (!PREF_KEY_BOOL(PLEASE_GROWL) ||
      (n && !PREF_KEY_BOOL(PLEASE_GROWL_NEW)) ||
      (!n && !PREF_KEY_BOOL(PLEASE_GROWL_PLAY))) {
    return;
  }

  BOOL liked = [[song nrating] intValue] == 1;
  NSString *title = [song title];
  if (liked) {
    title = [NSString stringWithFormat:@"👍 %@", title];
  }

  UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
  [content setTitle:title];
  [content setBody:[NSString stringWithFormat:@"%@\n%@", [song artist], [song album]]];
  [content setCategoryIdentifier:liked ? CATEGORY_SONG_LIKED : CATEGORY_SONG];

  UNNotificationAttachment *attachment = [self attachmentForImage:image];
  if (attachment != nil) {
    [content setAttachments:@[attachment]];
  }

  UNNotificationRequest *request =
    [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                         content:content
                                         trigger:nil];
  [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
    if (error != nil) {
      NSLog(@"Couldn't show song notification: %@", error);
    }
  }];
}

/******************************************************************************
 * Implementation of UNUserNotificationCenterDelegate
 ******************************************************************************/

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  /* always show notifications, even if the application is active */
  completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
  dispatch_async(dispatch_get_main_queue(), ^{
    PlaybackController *playback = [HMSAppDelegate playback];
    NSString *actionID = [response actionIdentifier];

    if ([actionID isEqualToString:@"like"]) {
      [playback like:self];
    } else if ([actionID isEqualToString:@"dislike"]) {
      [playback dislike:self];
    } else if ([actionID isEqualToString:@"next"]) {
      [playback next:self];
    } else if ([actionID isEqualToString:UNNotificationDefaultActionIdentifier]) {
      // Banner was clicked, so bring up and focus main UI
      [[HMSAppDelegate window] orderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
    }

    // Only way to get this notification to be removed from center
    [center removeAllDeliveredNotifications];
    completionHandler();
  });
}

@end
