//
//  ZBPackageListTableViewController.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#import "PackageIconDownloader.h"
#import "ZBPackageListTableViewController.h"
#import <Database/ZBDatabaseManager.h>
#import <Packages/Helpers/ZBPackage.h>
#import <Packages/Helpers/ZBPackageActionsManager.h>
#import <Queue/ZBQueue.h>
#import <ZBTabBarController.h>
#import <Repos/Helpers/ZBRepo.h>
#import <Packages/Helpers/ZBPackageTableViewCell.h>
#import <UIColor+GlobalColors.h>
#import <ZBAppDelegate.h>

@interface ZBPackageListTableViewController () <UIScrollViewDelegate> {
    NSArray *packages;
    NSArray *updates;
    BOOL needsUpdatesSection;
    int totalNumberOfPackages;
    int numberOfPackages;
    int databaseRow;
}

@property (nonatomic, strong) NSMutableDictionary *imageDownloadsInProgress;
@end

@implementation ZBPackageListTableViewController

@synthesize repo;
@synthesize section;
@synthesize databaseManager;

- (id)init {
    self = [super init];
    
    if (self) {
        if (!databaseManager) {
            databaseManager = [ZBDatabaseManager sharedInstance];
        }
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        if (!databaseManager) {
            databaseManager = [ZBDatabaseManager sharedInstance];
        }
    }
    
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if ([repo repoID] == 0) {
        [self configureNavigationButtons];
        [self refreshTable];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UITabBarItem *packagesTabBarItem = [self.tabBarController.tabBar.items objectAtIndex:2];
            
            if ([self->updates count] > 0) {
                [packagesTabBarItem setBadgeValue:[NSString stringWithFormat:@"%lu", (unsigned long)[self->updates count]]];
                [[UIApplication sharedApplication] setApplicationIconBadgeNumber:[self->updates count]];
            }
            else {
                [packagesTabBarItem setBadgeValue:nil];
                [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
            }
        });
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _imageDownloadsInProgress = [NSMutableDictionary dictionary];
    if ([repo repoID] == 0) {
        [self configureNavigationButtons];
        [self refreshTable];
    }
    else {
        packages = [databaseManager packagesFromRepo:repo inSection:section numberOfPackages:100 startingAt:0];
        databaseRow = 99;
        numberOfPackages = (int)[packages count];
        if (section != NULL) {
            totalNumberOfPackages = [databaseManager numberOfPackagesInRepo:repo section:section];
        }
        else {
            totalNumberOfPackages = [databaseManager numberOfPackagesInRepo:repo section:NULL];
        }
    }
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor tableViewBackgroundColor];
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBPackageTableViewCell" bundle:nil]
         forCellReuseIdentifier:@"packageTableViewCell"];
    
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.view];
    }
}

- (void)configureNavigationButtons {
    if ([repo repoID] == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->needsUpdatesSection) {
                UIBarButtonItem *updateButton = [[UIBarButtonItem alloc] initWithTitle:@"Upgrade All" style:UIBarButtonItemStylePlain target:self action:@selector(upgradeAll)];
                self.navigationItem.rightBarButtonItem = updateButton;
            }
            else {
                self.navigationItem.rightBarButtonItem = nil;
            }
            
            if ([[ZBQueue sharedInstance] hasObjects]) {
                UIBarButtonItem *queueButton = [[UIBarButtonItem alloc] initWithTitle:@"Queue" style:UIBarButtonItemStylePlain target:self action:@selector(presentQueue)];
                self.navigationItem.leftBarButtonItem = queueButton;
            }
            else {
                self.navigationItem.leftBarButtonItem = nil;
            }
        });
    }
}

- (void)refreshTable {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->packages = [self->databaseManager installedPackages];
        self->numberOfPackages = (int)[self->packages count];
        
        NSArray *_updates = [self->databaseManager packagesWithUpdates];
        self->needsUpdatesSection = [_updates count] > 0;

        if (self->needsUpdatesSection) {
            self->updates = _updates;
        }
        
        [self.tableView reloadData];
        
    });
}

- (void)loadNextPackages {
    if (databaseRow + 200 <= totalNumberOfPackages) {
        NSArray *nextPackages = [databaseManager packagesFromRepo:repo inSection:section numberOfPackages:200 startingAt:databaseRow];
        packages = [packages arrayByAddingObjectsFromArray:nextPackages];
        numberOfPackages = (int)[packages count];
        databaseRow += 199;
    }
    else if (totalNumberOfPackages - (databaseRow + 200) != 0) {
        NSArray *nextPackages = [databaseManager packagesFromRepo:repo inSection:section numberOfPackages:totalNumberOfPackages - (databaseRow + 200) startingAt:databaseRow];
        packages = [packages arrayByAddingObjectsFromArray:nextPackages];
        numberOfPackages = (int)[packages count];
        databaseRow += 199;
    }
}

- (void)upgradeButton {
    if (needsUpdatesSection) {
        UIBarButtonItem *updateButton = [[UIBarButtonItem alloc] initWithTitle:@"Upgrade All" style:UIBarButtonItemStylePlain target:self action:@selector(upgradeAll)];
        self.navigationItem.rightBarButtonItem = updateButton;
    }
    else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)queueButton {
    if ([[ZBQueue sharedInstance] hasObjects]) {
        UIBarButtonItem *queueButton = [[UIBarButtonItem alloc] initWithTitle:@"Queue" style:UIBarButtonItemStylePlain target:self action:@selector(presentQueue)];
        self.navigationItem.leftBarButtonItem = queueButton;
    }
    else {
        self.navigationItem.leftBarButtonItem = nil;
    }
}

- (void)presentQueue {
    [ZBPackageActionsManager presentQueue:self parent:nil];
}

- (void)upgradeAll {
    ZBQueue *queue = [ZBQueue sharedInstance];
    
    [queue addPackages:updates toQueue:ZBQueueTypeUpgrade];
    [self presentQueue];
}

- (ZBPackage *)packageAtIndexPath:(NSIndexPath *)indexPath {
    if (needsUpdatesSection && indexPath.section == 0) {
        return (ZBPackage *)[updates objectAtIndex:indexPath.row];
    }
    else {
        return (ZBPackage *)[packages objectAtIndex:indexPath.row];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (needsUpdatesSection) {
        return 2;
    }
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (needsUpdatesSection && section == 0) {
        return updates.count;
    }
    else {
        if (self.section != NULL) {
            return [databaseManager numberOfPackagesInRepo:repo section:self.section];
        }
        else {
            return [databaseManager numberOfPackagesInRepo:repo section:NULL];
        }
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(ZBPackageTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!needsUpdatesSection || indexPath.section != 0) {
        if ((indexPath.row - 1 >= [packages count] - ([packages count] / 10)) && ([repo repoID] != 0)) {
            [self loadNextPackages];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackageTableViewCell *cell = (ZBPackageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"packageTableViewCell" forIndexPath:indexPath];
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    [cell updateData:package];
    if (!package.iconImage) {
        NSURL *testURL = [NSURL URLWithString:package.iconPath];
        if (testURL && testURL.scheme && testURL.host && !testURL.isFileURL && self.tableView.dragging == NO && self.tableView.decelerating == NO) {
            [self startIconDownload:package atIndexPath:indexPath];
            cell.iconImageView.image = [UIImage imageNamed:@"Other"];
        } else {
            cell.iconImageView.image = [UIImage imageNamed:@"Other"];
        }
    }
    else {
        cell.iconImageView.image = package.iconImage;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self performSegueWithIdentifier:@"seguePackagesToPackageDepiction" sender:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 65;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, tableView.frame.size.width - 10, 18)];

    [label setFont:[UIFont boldSystemFontOfSize:15]];
    if ([repo repoID] == 0 && needsUpdatesSection && section == 0) {
        [label setText:@"Available Upgrades"];
    }
    else if (needsUpdatesSection) {
        [label setText:@"Installed Packages"];
    }
    else {
        [label setText:@""];
    }
    [view addSubview:label];
    
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
    // align label from the left and right
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-16-[label]-10-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(label)]];
    
    // align label from the bottom
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[label]-5-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(label)]];

    
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (([repo repoID] == 0 && needsUpdatesSection && section == 0)){
        return 35;
    }
    else if (needsUpdatesSection) {
        return 25;
    }
    else {
        return 10;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 5;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    return [ZBPackageActionsManager rowActionsForPackage:package indexPath:indexPath viewController:self parent:nil];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView setEditing:NO animated:YES];
}

#pragma mark - Navigation

- (void)setDestinationVC:(NSIndexPath *)indexPath destination:(ZBPackageDepictionViewController *)destination {
    
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    
    destination.package = package;
    destination.parent = self;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"seguePackagesToPackageDepiction"]) {
        ZBPackageDepictionViewController *destination = (ZBPackageDepictionViewController *)[segue destinationViewController];
        NSIndexPath *indexPath = sender;
        
        [self setDestinationVC:indexPath destination:destination];
    }
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location {
    NSIndexPath *indexPath = [self.tableView
                              indexPathForRowAtPoint:location];
    
    ZBPackageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    previewingContext.sourceRect = cell.frame;
    
    ZBPackageDepictionViewController *packageDepictionVC = (ZBPackageDepictionViewController*)[self.storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
    
    
    [self setDestinationVC:indexPath destination:packageDepictionVC];

    return packageDepictionVC;
    
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit {
    [self.navigationController pushViewController:viewControllerToCommit animated:YES];
}

- (void)startIconDownload:(ZBPackage *)package atIndexPath: (NSIndexPath *)indexPath
{
    if (package.iconImage != NULL) {
        ZBPackageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        cell.iconImageView.image = package.iconImage;
    }
    else {
        NSURL *testURL = [NSURL URLWithString:package.iconPath];
        if (testURL && testURL.scheme && testURL.host && !testURL.isFileURL) {
            PackageIconDownloader *iconDownloader = (self.imageDownloadsInProgress)[indexPath];
            if (iconDownloader == nil)
            {
                iconDownloader = [[PackageIconDownloader alloc] init];
                iconDownloader.package = package;
                [iconDownloader setCompletionHandler:^{
                    ZBPackageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                    cell.iconImageView.image = package.iconImage;
                    [self.imageDownloadsInProgress removeObjectForKey:indexPath];
                    
                }];
                (self.imageDownloadsInProgress)[indexPath] = iconDownloader;
                [iconDownloader startDownload];
            }
        }
    }
}

- (void)terminateAllDownloads
{
    // terminate all pending download connections
    NSArray *allDownloads = [self.imageDownloadsInProgress allValues];
    [allDownloads makeObjectsPerformSelector:@selector(cancelDownload)];
    
    [self.imageDownloadsInProgress removeAllObjects];
}

- (void)loadImagesForOnscreenRows
{
    if (self->packages.count > 0)
    {
        NSArray *visiblePaths = [self.tableView indexPathsForVisibleRows];
        for (NSIndexPath *indexPath in visiblePaths)
        {
            ZBPackage *package = (self->packages)[indexPath.row];
            
            if (!package.iconImage)
            {
                [self startIconDownload:package atIndexPath:indexPath];
            }
        }
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate)
    {
        [self loadImagesForOnscreenRows];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self loadImagesForOnscreenRows];
}

- (void)dealloc
{
    [self terminateAllDownloads];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    [self terminateAllDownloads];
}

@end
