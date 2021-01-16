//
//  ZBSectionSelectorTableViewController.m
//  Zebra
//
//  Created by Wilson Styres on 3/22/20.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

#import "ZBSectionSelectorTableViewController.h"
#import "UITableView+Settings.h"
#import "ZBOptionSettingsTableViewCell.h"

#import <ZBSettings.h>
#import <Managers/ZBSourceManager.h>
#import <Extensions/UIImageView+Zebra.h>
#import <Extensions/UIColor+GlobalColors.h>
#import <Model/ZBSource.h>

@interface ZBSectionSelectorTableViewController () {
    NSMutableArray *sections;
    NSMutableArray *selectedSections;
    NSMutableArray *selectedIndexes;
}
@end

@implementation ZBSectionSelectorTableViewController

#pragma mark - View Controller Lifecycle

- (id)init {
    self = [super init];
    
    if (self) {
        selectedSections = [NSMutableArray new];
        selectedIndexes = [NSMutableArray new];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"Select a Section", @"");
    
    NSMutableArray *allSections = [[[ZBSourceManager sharedInstance] allSections] mutableCopy];
    [allSections sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NSString *section1 = [self localizedSection:obj1];
        NSString *section2 = [self localizedSection:obj2];
            
        return [section1 compare:section2];
    }];
    
    NSArray *filteredSections = [ZBSettings filteredSections];
    
    [allSections removeObjectsInArray:filteredSections];
    
    sections = allSections;
    
    [self layoutNaviationButtons];
    [self.tableView registerCellType:ZBOptionSettingsCell];
}

- (NSString *)localizedSection:(NSString *)section {
    NSRange range = [section rangeOfString:@"("];

    if (range.length > 0) {
        NSString *section_ = [[section substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        return [NSString stringWithFormat:@"%@ %@", NSLocalizedString(section_, @""), [section substringFromIndex:range.location]];
    } else {
        return NSLocalizedString(section, @"");
    }
}

#pragma mark - Bar Button Actions

- (void)layoutNaviationButtons {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Add", @"") style:UIBarButtonItemStyleDone target:self action:@selector(addSections)];
    self.navigationItem.rightBarButtonItem.enabled = [selectedIndexes count];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"") style:UIBarButtonItemStylePlain target:self action:@selector(goodbye)];
}

- (void)addSections {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.sectionsSelected(self->selectedSections);
    });
    
    [self goodbye];
}

- (void)goodbye {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return sections.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBOptionSettingsTableViewCell *cell = [tableView dequeueOptionSettingsCellForIndexPath:indexPath];
    
    cell.textLabel.text = sections[indexPath.row];
    
    cell.imageView.image = [ZBSource imageForSection:sections[indexPath.row]];
    [cell.imageView resize:CGSizeMake(32, 32) applyRadius:YES];
    
    [cell setChosen:[selectedIndexes containsObject:indexPath]];
    [cell applyStyling];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *section = sections[indexPath.row];
    
    if ([selectedIndexes containsObject:indexPath]) {
        [selectedIndexes removeObject:indexPath];
        [selectedSections removeObject:section];
    }
    else {
        [selectedIndexes addObject:indexPath];
        [selectedSections addObject:section];
    }
    
    [self chooseUnchooseOptionAtIndexPath:indexPath];
    [self layoutNaviationButtons];
}

- (NSString *)stripSectionName:(NSString *)section {
    NSArray *components = [section componentsSeparatedByString:@"("];
    return [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end
