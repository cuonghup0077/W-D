//
//  ZBTabBarController.h
//  Zebra
//
//  Created by Wilson Styres on 3/15/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

@import UIKit;

#ifndef _TABBAR_H_
#define _TABBAR_H

NS_ASSUME_NONNULL_BEGIN

@interface ZBTabBarController : UITabBarController <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSString * _Nullable forwardToPackageID;
@property (nonatomic, strong) NSString * _Nullable forwardedSourceBaseURL;
- (void)openQueue:(BOOL)openPopup;
- (void)updateQueueBar;
- (void)forwardToPackage;
- (void)updateQueueBarPackageCount:(int)count;
- (void)closeQueue;
- (void)requestSourceRefresh;
@end

NS_ASSUME_NONNULL_END

#endif
