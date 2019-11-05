//
//  ZBTabBarController.h
//  Zebra
//
//  Created by Wilson Styres on 3/15/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Database/ZBDatabaseDelegate.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZBTabBarController : UITabBarController <ZBDatabaseDelegate>
@property (nonatomic, strong) NSString *forwardToPackageID;
@property (nonatomic, strong) NSString *forwardedRepoBaseURL;
@property (nonatomic, strong) NSMutableDictionary *repoBusyList;
- (void)setPackageUpdateBadgeValue:(int)updates;
- (void)setRepoRefreshIndicatorVisible:(BOOL)visible;
- (void)openQueue:(BOOL)openPopup;
- (void)clearRepos;
- (void)updateQueueNav;
- (void)updateQueueBar;
- (void)forwardToPackage;
- (void)updateQueueBarData;
@end

NS_ASSUME_NONNULL_END
