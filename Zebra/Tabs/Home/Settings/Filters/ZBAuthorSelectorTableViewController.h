//
//  ZBAuthorSelectorTableViewController.h
//  Zebra
//
//  Created by Wilson Styres on 3/22/20.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

#import "ZBSettingsTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZBAuthorSelectorTableViewController : ZBSettingsTableViewController <UISearchControllerDelegate, UISearchBarDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UISearchController *searchController;
@property void (^authorsSelected)(NSDictionary *selectedAuthors);
@end

NS_ASSUME_NONNULL_END
