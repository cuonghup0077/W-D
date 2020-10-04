//
//  ZBNotificationManager.m
//  Zebra
//
//  Created by Arthur Chaloin on 06/06/2020.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

#import "ZBNotificationManager.h"
#import <Database/ZBDatabaseManager.h>
#import <Tabs/Sources/Helpers/ZBSource.h>
#import <Tabs/Sources/Helpers/ZBSourceManager.h>

@interface ZBNotificationManager ()

@property () BackgroundCompletionHandler completionHandler;
@property () ZBPackageList *oldUpdates;

- (void)fetchCompleted:(UIBackgroundFetchResult)result;

@end

@implementation ZBNotificationManager

+ (id)sharedInstance {
   static ZBNotificationManager *instance = nil;
   if (instance == nil) {
       instance = [ZBNotificationManager new];
   }
   return instance;
}

- (void)ensureNotificationAccess {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[Zebra] Error: %@", error.localizedDescription);
        } else if (!granted) {
            NSLog(@"[Zebra] Authorization was not granted.");
        } else {
            NSLog(@"[Zebra] Notification access granted.");
        }
    }];
    
    center.delegate = self;
}

- (void)performBackgroundFetch:(BackgroundCompletionHandler)completionHandler {
    ZBDatabaseManager *databaseManager = [ZBDatabaseManager sharedInstance];
    ZBSourceManager *sourceManager = [ZBSourceManager sharedInstance];
    
    self.completionHandler = completionHandler;
    self.oldUpdates = [databaseManager packagesWithUpdates];

    [sourceManager addDelegate:self];
    [sourceManager refreshSourcesUsingCaching:YES userRequested:YES error:nil];
}

- (UIBackgroundFetchResult)notifyNewUpdatesBetween:(ZBPackageList *)oldUpdates
                                        newUpdates:(ZBPackageList *)newUpdates {
    UIBackgroundFetchResult result = UIBackgroundFetchResultNoData;
    ZBPackageList *packagesToNotify = [ZBPackageList new];
    
    for (ZBPackage *package in newUpdates) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"identifier == %@", package.identifier];
        NSArray<ZBPackage *> *filteredPackages = [oldUpdates filteredArrayUsingPredicate:predicate];
        
        if (filteredPackages.count > 1) {
            NSLog(@"[Zebra] WARNING: Received multiple updates for the same package. This is most probably a developer error.");
            continue;
        }
        else if (filteredPackages.count <= 0) {
            [packagesToNotify addObject:package];
        }
        else {
            ZBPackage *oldPackage = filteredPackages[0];
            
            if (![package.version isEqualToString:oldPackage.version]) {
                [packagesToNotify addObject:package];
            }
        }
    }

    if (packagesToNotify.count > 0) {
        [self notifyUpdateForPackages:packagesToNotify];
        result = UIBackgroundFetchResultNewData;
    }

    return result;
}

- (void)notifyUpdateForPackages:(ZBPackageList *)packages {
    if (packages.count == 1) {
        ZBPackage *package = packages[0];

        NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Update available for %@", @""), package.name];
        NSString *text = [NSString stringWithFormat:NSLocalizedString(@"Version %@ is available on %@.", @""), package.version, [package.source label]];

        [self notify:text withTitle:title withUserInfo:@{
            @"openURL": [NSString stringWithFormat:@"zbra://packages/%@", package.identifier],
        }];
    }
    else if (packages.count > 1) {
        NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%lu updates available", @""), (unsigned long)packages.count];
        NSString *text = [NSString stringWithFormat:NSLocalizedString(@"%@ and %lu more can be updated.", @""), packages[0].name, packages.count - 1];

        [self notify:text withTitle:title withUserInfo:@{
            @"openURL": @"zbra://changes",
        }];
    }
}

- (void)notify:(NSString *)body withTitle:(NSString *)title withUserInfo:(NSDictionary *)userInfo {
    NSDate* now = [NSDate date];
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *date = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond|NSCalendarUnitTimeZone fromDate:[now dateByAddingTimeInterval:3]];

    UNCalendarNotificationTrigger* trigger = [UNCalendarNotificationTrigger
           triggerWithDateMatchingComponents:date repeats:NO];

    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.userInfo = userInfo;

    UNNotificationRequest* request = [UNNotificationRequest
           requestWithIdentifier:@"xyz.willy.Zebra.updates" content:content trigger:trigger];

    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
       if (error != nil) {
           NSLog(@"[Zebra] %@", error.localizedDescription);
       }
    }];
}

- (void)fetchCompleted:(UIBackgroundFetchResult)result {
    self.oldUpdates = nil;

    if (self.completionHandler != nil) {
        BackgroundCompletionHandler completionHandler = self.completionHandler;
        self.completionHandler = nil;
        completionHandler(result);
    }
}

#pragma mark Source Delegate

- (void)packageUpdatesAvailable:(int)numberOfUpdates {
    if (numberOfUpdates <= 0) {
        [self fetchCompleted:UIBackgroundFetchResultNoData];
        return;
    }

    ZBDatabaseManager *databaseManager = [ZBDatabaseManager sharedInstance];
    ZBPackageList *newUpdates = [databaseManager packagesWithUpdates];

    UIBackgroundFetchResult result = [self notifyNewUpdatesBetween:self.oldUpdates newUpdates:newUpdates];
    [self fetchCompleted:result];
}

#pragma mark UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(nonnull UNNotificationResponse *)response withCompletionHandler:(nonnull void (^)(void))completionHandler {
    
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSURL *openURL = [NSURL URLWithString:[userInfo objectForKey:@"openURL"]];
    
    if (!openURL) {
        completionHandler();
        return;
    }

    [UIApplication.sharedApplication openURL:openURL
                                     options:[NSMutableDictionary dictionary]
                           completionHandler:^(BOOL _) {
        completionHandler();
    }];
}

@end
