//
//  ZBSourceListTableViewController.m
//  Zebra
//
//  Created by Wilson Styres on 12/3/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#import "ZBSourceListViewController.h"
#import "ZBSourceAddViewController.h"
#import "ZBSourceSectionsListTableViewController.h"

#import <ZBDevice.h>

#import <Extensions/UIColor+GlobalColors.h>
#import <Extensions/UIAlertController+Zebra.h>
#import <Tabs/Sources/Helpers/ZBSource.h>
#import <Tabs/Sources/Helpers/ZBSourceManager.h>
#import <Tabs/Sources/Views/ZBSourceTableViewCell.h>

@interface ZBSourceListViewController () {
    UISearchController *searchController;
    NSMutableArray *sourcesToRemove;
    UIBarButtonItem *addButton;
    BOOL hasProblems;
}
@end

@implementation ZBSourceListViewController

#pragma mark - Initializers

- (id)init {
    if (@available(iOS 13.0, *)) {
        self = [super initWithStyle:UITableViewStyleInsetGrouped];
    } else {
        self = [super initWithStyle:UITableViewStyleGrouped];
    }
    
    if (self) {
        self.title = NSLocalizedString(@"Sources", @"");
        self.tableView.allowsMultipleSelectionDuringEditing = YES;
        
        searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
        searchController.obscuresBackgroundDuringPresentation = NO;
        searchController.searchResultsUpdater = self;
        searchController.delegate = self;
        searchController.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        
        sources = [sourceManager.sources mutableCopy];
        filteredSources = [sources copy];
        hasProblems = NO;
    }
    
    return self;
}

#pragma mark - View Controller Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(presentAddView)];
    self.navigationItem.rightBarButtonItem = addButton;
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBSourceTableViewCell" bundle:nil] forCellReuseIdentifier:@"sourceCell"];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)presentAddView {
    ZBSourceAddViewController *addView = [[ZBSourceAddViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:addView];
    
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)presentAddViewWithURL:(NSURL *)url {
    ZBSourceAddViewController *addView = [[ZBSourceAddViewController alloc] initWithURL:url];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:addView];
    
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)removeSources {
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to remove %lu sources?", @""), (unsigned long)sourcesToRemove.count];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Are you sure?", @"") message:message preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self->sourceManager removeSources:[NSSet setWithArray:self->sourcesToRemove] error:nil];
    }];
    [alert addAction:confirm];
    
    UIAlertAction *deny = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:deny];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    
    if (editing) {
        if (!sourcesToRemove) sourcesToRemove = [NSMutableArray new];
        
        UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(removeSources)];
        deleteButton.enabled = NO;
        self.navigationItem.rightBarButtonItems = @[addButton, deleteButton];
    }
    else {
        self.navigationItem.rightBarButtonItems = @[addButton];
        [sourcesToRemove removeAllObjects];
    }
}

- (void)handleURL:(NSURL *)url {
    NSString *scheme = [url scheme];
    NSArray *choices = @[@"file", @"zbra"];
    
    switch ([choices indexOfObject:scheme]) {
        case 0:
            // TODO: Re-implement source importing from .list
            break;
        case 1: {
            NSString *path = [url path];
            if (![path isEqualToString:@""]) {
                NSArray *components = [path pathComponents];
                if ([components count] >= 4) {
                    NSString *urlString = [path componentsSeparatedByString:@"/add/"][1];
                    if (![urlString hasSuffix:@"/"]) {
                        urlString = [urlString stringByAppendingString:@"/"];
                    }
                    
                    NSURL *url;
                    if ([urlString containsString:@"https://"] || [urlString containsString:@"http://"]) {
                        url = [NSURL URLWithString:urlString];
                    } else {
                        url = [NSURL URLWithString:[@"https://" stringByAppendingString:urlString]];
                    }
                    
                    if (url && url.scheme && url.host) {
                        [self presentAddViewWithURL:url];
                    } else {
                        [self presentAddView];
                    }
                }
                break;
            }
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return hasProblems + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0 && hasProblems) {
        return 1;
    } else {
        return filteredSources.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && hasProblems) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"problemChild"];
        
        return cell;
    }
    else {
        ZBSourceTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sourceCell"];
        [cell setSource:filteredSources[indexPath.row]];
        
        return cell;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && hasProblems) {
        return NO;
    }
    else {
        ZBSource *source = filteredSources[indexPath.row];
        return [source canDelete];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && hasProblems) {
        cell.detailTextLabel.text = @"Some of your sources have warnings and errors.";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.textColor = [UIColor secondaryTextColor];
        cell.detailTextLabel.numberOfLines = 0;
        cell.imageView.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
    }
    else {
        ZBBaseSource *source = filteredSources[indexPath.row];
        
        BOOL busy = [sourceManager isSourceBusy:source];
        [(ZBSourceTableViewCell *)cell setSpinning:busy];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBSource *source = filteredSources[indexPath.row];
    if (!self.editing) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if ([source isKindOfClass:[ZBSource class]]) {
            ZBSourceSectionsListTableViewController *sections = [[ZBSourceSectionsListTableViewController alloc] initWithSource:source editOnly:NO];
            [self.navigationController pushViewController:sections animated:YES];
        }
    }
    else {
        [sourcesToRemove addObject:source];
        
        self.navigationItem.rightBarButtonItems[1].enabled = sourcesToRemove.count;
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.editing) {
        ZBSource *source = filteredSources[indexPath.row];
        if ([sourcesToRemove containsObject:source]) {
            [sourcesToRemove removeObject:source];
        }
        self.navigationItem.rightBarButtonItems[1].enabled = sourcesToRemove.count;
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 || !hasProblems) {
        ZBSource *source = filteredSources[indexPath.row];
        NSError *error;
        if (source.errors && source.errors.count) {
            error = source.errors.firstObject;
        }
        else if (source.warnings && source.warnings.count) {
            error = source.warnings.firstObject;
        }
        
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithError:error];
        
            switch (error.code) {
                case ZBSourceWarningInsecure: {
                    UIAlertAction *switchAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Switch to HTTPS", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    }];
                    [alert addAction:switchAction];
                    
                    UIAlertAction *continueAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:nil];
                    [alert addAction:continueAction];
                    break;
                }
                default: {
                    UIAlertAction *switchAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Remove Source", @"") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                        
                    }];
                    [alert addAction:switchAction];
                    
                    UIAlertAction *continueAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:nil];
                    [alert addAction:continueAction];
                    break;
                }
            }
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBSource *source = filteredSources[indexPath.row];
    
    UIContextualAction *copyAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:NSLocalizedString(@"Copy",@"") handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
        [pasteBoard setString:source.repositoryURI];
        completionHandler(YES);
    }];
    
    copyAction.image = [UIImage imageNamed:@"doc_fill"];
    copyAction.backgroundColor = [UIColor systemTealColor];
    
    return [UISwipeActionsConfiguration configurationWithActions:@[copyAction]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBSource *source = filteredSources[indexPath.row];
    
    NSMutableArray *actions = [NSMutableArray new];
    if ([source canDelete]) {
        UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:NSLocalizedString(@"Delete", @"") handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            NSError *error = NULL;
            [self->sourceManager removeSources:[NSSet setWithArray:@[source]] error:&error];
            
            completionHandler(error == NULL);
        }];
        deleteAction.image = [UIImage imageNamed:@"delete_left"];
        [actions addObject:deleteAction];
    }
    
    UIContextualAction *refreshAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:NSLocalizedString(@"Refresh", @"") handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [self->sourceManager refreshSources:[NSSet setWithArray:@[source]] useCaching:NO error:nil];
        completionHandler(YES);
    }];
    refreshAction.image = [UIImage imageNamed:@"arrow_clockwise"];
    [actions addObject:refreshAction];
    
    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

#pragma mark - UISearchResultsUpdating

- (void)filterSourcesForSearchTerm:(NSString *)searchTerm {
    if ([[searchTerm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@""]) {
        filteredSources = [sources copy];
    }
    else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(repositoryURI CONTAINS[cd] %@) OR (origin CONTAINS[cd] %@)", searchTerm, searchTerm];
        
        filteredSources = [sources filteredArrayUsingPredicate:predicate];
    }
}

- (void)updateSearchResultsForSearchController:(nonnull UISearchController *)searchController {
    NSString *searchTerm = searchController.searchBar.text;
    [self filterSourcesForSearchTerm:searchTerm];
    
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:hasProblems] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - ZBSourceDelegate

- (void)startedDownloadForSource:(ZBBaseSource *)source {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:(ZBSource *)source] inSection:self->hasProblems];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)finishedDownloadForSource:(ZBBaseSource *)source {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:(ZBSource *)source] inSection:self->hasProblems];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)startedImportForSource:(ZBBaseSource *)source {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:(ZBSource *)source] inSection:self->hasProblems];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)finishedImportForSource:(ZBBaseSource *)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSIndexPath *oldIndexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:(ZBSource *)source] inSection:self->hasProblems];
        
        self->sources = [self->sourceManager.sources mutableCopy];
        [self filterSourcesForSearchTerm:self->searchController.searchBar.text];
        
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:(ZBSource *)source] inSection:self->hasProblems];
        
        if ([oldIndexPath isEqual:newIndexPath]) {
            [self.tableView reloadRowsAtIndexPaths:@[oldIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        else {
            [self.tableView beginUpdates];
            [self.tableView deleteRowsAtIndexPaths:@[oldIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
        }
    });
}

- (void)finishedSourceRefresh {
    [super finishedSourceRefresh];
    
    NSPredicate *search = [NSPredicate predicateWithFormat:@"errors != nil AND errors[SIZE] > 0"];
    hasProblems = [sources filteredArrayUsingPredicate:search].count;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->hasProblems && self.tableView.numberOfSections == 1) {
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if (!self->hasProblems && self.tableView.numberOfSections == 2) {
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    });
}

- (void)addedSources:(NSSet<ZBBaseSource *> *)sources {
    self->sources = [sourceManager.sources mutableCopy];
    [self filterSourcesForSearchTerm:searchController.searchBar.text];
    
    NSMutableArray *indexPaths = [NSMutableArray new];
    for (ZBSource *source in sources) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:source] inSection:self->hasProblems];
        [indexPaths addObject:indexPath];
    }
    
    [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)removedSources:(NSSet<ZBBaseSource *> *)sources {
    NSMutableArray *indexPaths = [NSMutableArray new];
    for (ZBSource *source in sources) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self->filteredSources indexOfObject:source] inSection:self->hasProblems];
        [indexPaths addObject:indexPath];
    }
    
    self->sources = [sourceManager.sources mutableCopy];
    [self filterSourcesForSearchTerm:searchController.searchBar.text];
    
    [self.tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
