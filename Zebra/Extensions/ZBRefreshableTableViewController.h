//
//  ZBRefreshableTableViewController.h
//  Zebra
//
//  Created by Thatchapon Unprasert on 17/6/2019
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBTableViewController.h"

#import <Managers/ZBSourceManager.h>
#import <Theme/ZBThemeManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZBRefreshableTableViewController : ZBTableViewController <ZBSourceDelegate> {
    ZBSourceManager *sourceManager;
}
- (void)layoutNavigationButtons;
- (void)layoutNavigationButtonsRefreshing;
- (void)layoutNavigationButtonsNormal;
@end

NS_ASSUME_NONNULL_END
