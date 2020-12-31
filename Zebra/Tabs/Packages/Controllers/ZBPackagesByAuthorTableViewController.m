//
//  ZBPackagesByAuthorTableViewController.m
//  Zebra
//
//  Created by midnightchips on 6/20/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

// I'm going to replace this class with a ZBPackageListController later so I'm not going to worry about it too much for now

#import "ZBPackagesByAuthorTableViewController.h"

#import <ZBAppDelegate.h>
#import <Extensions/UIColor+GlobalColors.h>
#import <Tabs/Packages/Helpers/ZBPackageActions.h>
#import <UI/Packages/Views/Cells/ZBPackageTableViewCell.h>
#import <Tabs/Packages/Controllers/ZBPackageViewController.h>
#import <Tabs/ZBTabBarController.h>

#import <Managers/ZBPackageManager.h>

@interface ZBPackagesByAuthorTableViewController () {
    NSArray <ZBPackage *> *moreByAuthor;
    ZBPackage *package;
}
@end

@implementation ZBPackagesByAuthorTableViewController

- (id)initWithPackage:(ZBPackage *)package {
    self = [super init];
    
    if (self) {
        self->package = package;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[ZBPackageManager sharedInstance] searchForPackagesByAuthorWithName:package.authorName email:package.authorEmail completion:^(NSArray <ZBPackage *> *packages) {
        self->moreByAuthor = packages;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBPackageTableViewCell" bundle:nil] forCellReuseIdentifier:@"packageTableViewCell"];
    self.navigationItem.title = package.authorName;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return moreByAuthor.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackageTableViewCell *cell = (ZBPackageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"packageTableViewCell" forIndexPath:indexPath];
    [cell setColors];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = moreByAuthor[indexPath.row];
    [(ZBPackageTableViewCell *)cell updateData:package];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = moreByAuthor[indexPath.row];
    if (package) {
        ZBPackageViewController *packageDepiction = [[ZBPackageViewController alloc] initWithPackage:package];
        
        [[self navigationController] pushViewController:packageDepiction animated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return ![[ZBAppDelegate tabBarController] isQueueBarAnimating];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = moreByAuthor[indexPath.row];
    return [ZBPackageActions swipeActionsForPackage:package inTableView:tableView];
}
    
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView setEditing:NO animated:YES];
}

@end
