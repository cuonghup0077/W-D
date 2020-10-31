//
//  ZBPackageListTableViewController.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#import <ZBAppDelegate.h>
#import <ZBLog.h>
#import <Tabs/ZBTab.h>
#import <ZBSettings.h>
#import <Tabs/Packages/Helpers/ZBPackagePartitioner.h>
#import "ZBPackageListTableViewController.h"
#import <Managers/ZBPackageManager.h>
#import <Model/ZBPackage.h>
#import <Tabs/Packages/Helpers/ZBPackageActions.h>
#import <Queue/ZBQueue.h>
#import <Tabs/ZBTabBarController.h>
#import <Model/ZBSource.h>
#import <UI/Packages/Views/Cells/ZBPackageTableViewCell.h>
#import <Extensions/UIColor+GlobalColors.h>
#import <Extensions/UIViewController+Extensions.h>
#import "ZBDevice.h"
#import <Tabs/Packages/Controllers/ZBPackageViewController.h>

@import FirebaseAnalytics;

@interface ZBPackageListTableViewController () {
    ZBPackageManager *packageManager;
    ZBSortingType selectedSortingType;
    NSArray <ZBBasePackage *> *packages;
    NSArray <ZBBasePackage *> *sortedPackages;
    NSMutableArray <ZBPackage *> *updates;
    NSMutableArray *sectionIndexTitles;
    UIBarButtonItem *queueButton;
    UIBarButtonItem *clearButton;
    BOOL needsUpdatesSection;
    BOOL isRefreshingTable;
    int totalNumberOfPackages;
    int numberOfPackages;
    int databaseRow;
    
    ZBSource *source;
    NSString *section;
}
@property (nonatomic, weak) ZBPackageViewController *previewPackageDepictionVC;
@end

@implementation ZBPackageListTableViewController

- (instancetype)initWithSource:(ZBSource *)source {
    return [self initWithSource:source section:NULL];
}

- (instancetype)initWithSource:(ZBSource *)source section:(NSString *_Nullable)section {
    self = [super initWithStyle:UITableViewStylePlain];
    
    if (self) {
        self->source = source;
        self->section = [section isEqualToString:@"ALL_PACKAGES"] ? NULL : section;
        
        if (self->source.remote) {
            if (self->section) {
                self.title = NSLocalizedString(self->section, @"");
            } else {
                self.title = NSLocalizedString(@"All Packages", @"");
            }
        } else {
            self.title = NSLocalizedString(@"Installed", @"");
        }
    }
    
    return self;
}

- (BOOL)useBatchLoad {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self applyLocalization];

    packageManager = [ZBPackageManager sharedInstance];
    selectedSortingType = ZBSortingTypeABC;//[ZBSettings packageSortingType];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBPackageTableViewCell" bundle:nil] forCellReuseIdentifier:@"packageTableViewCell"];
}

- (void)applyLocalization {
    // This isn't exactly "best practice", but this way the text in IB isn't useless.
    self.navigationItem.title = NSLocalizedString([self.navigationItem.title capitalizedString], @"");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshTable];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ZBDatabaseCompletedUpdate" object:nil];
}

- (void)layoutNavigationButtonsNormal {
    if (!source.remote) {
        [self configureUpgradeButton];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            UIBarButtonItem *shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sharePackages)];
            self.navigationItem.leftBarButtonItem = shareButton;
        });
    } else {
//        [self configureLoadMoreButton];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.leftBarButtonItem = nil;
        });
    }
    [self configureSegmentedController];
}

- (void)updateCollation {
//    switch (selectedSortingType) {
//        case ZBSortingTypeABC:
            self.tableData = [self partitionObjects:packages collationStringSelector:@selector(name)];
//            break;
//        case ZBSortingTypeDate:
//            self.tableData = [self partitionObjects:packages collationStringSelector:source.sourceID ? @selector(lastSeenDate) : @selector(installedDate)];
//            break;
//        default:
//            break;
//    }
}

- (void)refreshTable {
    if (isRefreshingTable)
        return;
    
    isRefreshingTable = YES;
    packages = [packageManager packagesFromSource:source];
    if (!source.remote) {
//        updates = [databaseManager packagesWithUpdates]; //TODO: Fix This
        
        NSUInteger totalUpdates = updates.count;
        needsUpdatesSection = totalUpdates != 0;
        
        UITabBarItem *packagesTabBarItem = [self.tabBarController.tabBar.items objectAtIndex:ZBTabPackages];
        [packagesTabBarItem setBadgeValue:totalUpdates ? [NSString stringWithFormat:@"%lu", (unsigned long)totalUpdates] : nil];
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:totalUpdates];
        
        isRefreshingTable = NO;
    }
    
    numberOfPackages = (int)[self->packages count];
        
    [self updateCollation];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)configureUpgradeButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->needsUpdatesSection) {
            UIBarButtonItem *updateButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Upgrade All", @"") style:UIBarButtonItemStylePlain target:self action:@selector(upgradeAll)];
            self.navigationItem.rightBarButtonItem = updateButton;
        } else {
            self.navigationItem.rightBarButtonItem = nil;
        }
    });
}

- (void)configureSegmentedController {
//    dispatch_async(dispatch_get_main_queue(), ^{
//        NSMutableArray *items = [@[NSLocalizedString(@"ABC", @""), NSLocalizedString(@"Date", @""), NSLocalizedString(@"Size", @"")] mutableCopy];
//        if (self->source.sourceID)
//            [items removeLastObject];
//        UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:items];
//        segmentedControl.selectedSegmentIndex = self->selectedSortingType;
//        [segmentedControl addTarget:self action:@selector(segmentedControlValueChanged:) forControlEvents:UIControlEventValueChanged];
//        self.navigationItem.titleView = segmentedControl;
//    });
}

- (void)installAll {
    NSMutableArray *installablePackages = [NSMutableArray new];
    for (ZBPackage *package in packages) {
        if (package.isInstalled || ![package canReinstall] || [package isPaid])
            continue;
        [installablePackages addObject:package];
    }
    [[ZBQueue sharedQueue] addPackages:installablePackages toQueue:ZBQueueTypeInstall];
}

- (void)sharePackages {
//    NSArray *packages = [databaseManager installedPackages:NO];
//    [packages sortedArrayUsingSelector:@selector(name)];
//
//    NSMutableArray *descriptions = [NSMutableArray new];
//    for (ZBPackage *package in packages) {
//        [descriptions addObject:[package description]];
//    }
//
//    NSString *fullList = [descriptions componentsJoinedByString:@"\n"];
//    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:@[fullList] applicationActivities:nil];
//    [self presentActivityController:controller];
}

// Share Sheet
- (void)presentActivityController:(UIActivityViewController *)controller {
    
    // for iPad: make the presentation a Popover
    controller.modalPresentationStyle = UIModalPresentationPopover;
    [self presentViewController:controller animated:YES completion:nil];
    
    UIPopoverPresentationController *popController = [controller popoverPresentationController];
    popController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popController.barButtonItem = self.navigationItem.leftBarButtonItem;
    
    // access the completion handler
    controller.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *error) {
        // react to the completion
        if (completed) {
            // user shared an item
            ZBLog(@"We used activity type %@", activityType);
        } else {
            // user cancelled
            ZBLog(@"We didn't want to share anything after all.");
        }
        
        if (error) {
            ZBLog(@"An Error occured: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

- (void)upgradeAll {
    NSUInteger beforeCount = [ZBQueue count];
    
    [ZBPackageActions performAction:ZBPackageActionUpgrade forPackages:updates completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadRowsAtIndexPaths:[self.tableView indexPathsForVisibleRows] withRowAnimation:UITableViewRowAnimationNone];
            NSUInteger afterCount = [ZBQueue count];
            if (beforeCount == afterCount) {
                [[ZBAppDelegate tabBarController] openQueue:YES];
            }
        });
    }];
}

- (ZBPackage *)packageAtIndexPath:(NSIndexPath *)indexPath {
    if (needsUpdatesSection && indexPath.section == 0) {
        return [updates objectAtIndex:indexPath.row];
    }
    if (selectedSortingType == ZBSortingTypeABC || selectedSortingType == ZBSortingTypeDate) {
        return [self objectAtSection:indexPath.section][indexPath.row];
    }
    return sortedPackages[indexPath.row];
}

- (void)segmentedControlValueChanged:(UISegmentedControl *)segmentedControl {
    selectedSortingType = (ZBSortingType)segmentedControl.selectedSegmentIndex;
    
    [ZBSettings setPackageSortingType:selectedSortingType];
    [self refreshTable];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (selectedSortingType == ZBSortingTypeABC || selectedSortingType == ZBSortingTypeDate) {
        return sectionIndexTitles.count + needsUpdatesSection;
    }
    return 1 + needsUpdatesSection;
}

- (NSInteger)trueSection:(NSInteger)section {
    return section - needsUpdatesSection;
}

- (NSArray * _Nullable)objectAtSection:(NSInteger)section {
    if (self.tableData.count == 0)
        return nil;
    NSInteger trueSection = [self trueSection:section];
    return trueSection < self.tableData.count ? self.tableData[trueSection] : nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (needsUpdatesSection && section == 0) {
        return updates.count;
    }
    if (selectedSortingType == ZBSortingTypeABC || selectedSortingType == ZBSortingTypeDate) {
        return [self objectAtSection:section].count;
    }
    return sortedPackages.count;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(ZBPackageTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    [cell updateData:package calculateSize:selectedSortingType == ZBSortingTypeInstalledSize showVersion:needsUpdatesSection && indexPath.section == 0];
//    if ([source sourceID] != 0 && self.batchLoad && self.continueBatchLoad && numberOfPackages != totalNumberOfPackages) {
//        NSInteger sectionsAmount = [tableView numberOfSections];
//        NSInteger rowsAmount = [tableView numberOfRowsInSection:indexPath.section];
//        if ((indexPath.section == sectionsAmount - 1) && (indexPath.row == rowsAmount - 1)) {
//            [self loadNextPackages];
//        }
//    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackageTableViewCell *cell = (ZBPackageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"packageTableViewCell" forIndexPath:indexPath];
    [cell setColors];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    ZBPackageViewController *depiction = [[ZBPackageViewController alloc] initWithPackage:package];
    
    [[self navigationController] pushViewController:depiction animated:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    BOOL isUpdateSection = !source.remote && needsUpdatesSection && section == 0;
    BOOL hasDataInSection = !isUpdateSection && [[self objectAtSection:section] count];
    if (isUpdateSection || hasDataInSection) {
        if (isUpdateSection) {
            return NSLocalizedString(@"Available Upgrades", @"");
        }
        if (hasDataInSection) {
            NSInteger trueSection = [self trueSection:section];
            if (selectedSortingType == ZBSortingTypeABC)
                return [self sectionIndexTitlesForTableView:tableView][trueSection];
            if (selectedSortingType == ZBSortingTypeDate)
                return [ZBPackagePartitioner titleForHeaderInDateSection:trueSection sectionIndexTitles:sectionIndexTitles dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
        }
        if (selectedSortingType == ZBSortingTypeInstalledSize) {
            return NSLocalizedString(@"Size", @"");
        }
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView numberOfRowsInSection:section] ? 30 : 0;
}

- (NSArray *)partitionObjects:(NSArray *)array collationStringSelector:(SEL)selector {
    sectionIndexTitles = [NSMutableArray array];
    return [ZBPackagePartitioner partitionObjects:array collationStringSelector:selector sectionIndexTitles:sectionIndexTitles packages:packages type:selectedSortingType];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    if (selectedSortingType == ZBSortingTypeABC)
        return sectionIndexTitles;
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index + needsUpdatesSection;
}

#pragma mark - Swipe actions

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return ![[ZBAppDelegate tabBarController] isQueueBarAnimating];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackage *package = [self packageAtIndexPath:indexPath];
    return [ZBPackageActions swipeActionsForPackage:package inTableView:tableView];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView setEditing:NO animated:YES];
}

#pragma mark - Navigation

// FIXME: Update for new depictions
//- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)){
//    typeof(self) __weak weakSelf = self;
//    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:^UIViewController * _Nullable{
//        return weakSelf.previewPackageDepictionVC;
//    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
//        weakSelf.previewPackageDepictionVC = (ZBPackageDepictionViewController*)[weakSelf.storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
//        [weakSelf setDestinationVC:indexPath destination:weakSelf.previewPackageDepictionVC];
//        return [UIMenu menuWithTitle:@"" children:[weakSelf.previewPackageDepictionVC contextMenuActionItemsInTableView:tableView]];
//    }];
//}

- (void)tableView:(UITableView *)tableView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator API_AVAILABLE(ios(13.0)){
    typeof(self) __weak weakSelf = self;
    [animator addCompletion:^{
        [weakSelf.navigationController pushViewController:weakSelf.previewPackageDepictionVC animated:YES];
    }];
}

//- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location {
//    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
//    ZBPackageTableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
//    previewingContext.sourceRect = cell.frame;
//    ZBPackageViewController *packageDepictionVC = (ZBPackageViewController*)[self.storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
//    [self setDestinationVC:indexPath destination:packageDepictionVC];
//    return packageDepictionVC;
//}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit {
    [self.navigationController pushViewController:viewControllerToCommit animated:YES];
}

//- (NSArray *)contextMenuActionItemsForIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(13.0)) {
//    if (!source || [databaseManager numberOfPackagesInSource:source section:section] > 400) return @[];
//    
//    NSString *title = NSLocalizedString(@"Install All", @"");
//    UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"tortoise"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
//        [self installAll];
//    }];
//    
//    return @[action];
//}

- (void)scrollToTop {
    [self.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForHeaderInSection:(NSInteger)section {
    return 0;
}

@end
