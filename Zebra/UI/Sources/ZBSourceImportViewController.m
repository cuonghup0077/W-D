//
//  ZBSourceImportViewController.m
//  Zebra
//
//  Created by Wilson Styres on 1/5/20.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

@import SDWebImage;

#import "ZBSourceImportViewController.h"
#import "ZBAppDelegate.h"

#import <Extensions/UINavigationBar+Extensions.h>
#import <Extensions/UIViewController+Extensions.h>
#import <Model/ZBSource.h>
#import <Managers/ZBSourceManager.h>
#import <UI/Sources/Views/Cells/ZBSourceTableViewCell.h>
#import <Extensions/UIColor+GlobalColors.h>

@interface ZBSourceImportViewController () {
    double individualIncrement;
    NSUInteger sourcesToVerify;
}
@property NSArray <ZBBaseSource *> *baseSources;
@property NSMutableDictionary <NSString *, NSString *> *titles;
@property NSMutableDictionary <NSString *, NSNumber *> *selectedSources;
@property ZBSourceManager *sourceManager;
@end

@implementation ZBSourceImportViewController

@synthesize baseSources;
@synthesize sourceFilesToImport;
@synthesize titles;
@synthesize sourceManager;
@synthesize selectedSources;

#pragma mark - Initializers

- (instancetype)init {
    self = [super init];
    
    if (self) {
        if (@available(iOS 13.0, *)) {
            self.modalInPresentation = YES;
        }
        
        titles = [NSMutableDictionary new];
        selectedSources = [NSMutableDictionary new];
        sourceManager = [ZBSourceManager sharedInstance];
        sourceFilesToImport = [NSMutableArray new];
    }
    
    return self;
}

- (instancetype)initWithPaths:(NSArray <NSURL *> *)filePaths extension:(NSString *)extension {
    self = [self init];
    
    if (self) {
        for (NSURL *url in filePaths) {
            BOOL isDirectory = NO;
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory];
            if (exists && isDirectory) { // If the location is a directory then add each individual file URL
                for (NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[url path] error:nil]) {
                    if ([[filename pathExtension] isEqualToString:extension]) {
                        NSURL *fileURL = [url URLByAppendingPathComponent:filename];
                        if (fileURL) [sourceFilesToImport addObject:fileURL];
                    }
                }
            }
            else if (exists && [[url pathExtension] isEqualToString:extension]) {
                [sourceFilesToImport addObject:url];
            }
        }
    }
    
    return self;
}

- (instancetype)initWithPaths:(NSArray <NSURL *> *)filePaths {
    return [self initWithPaths:filePaths extension:@"list"];
}

- (instancetype)initWithSources:(NSSet <ZBBaseSource *> *)sources {
    self = [self init];
    
    if (self) {
        NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"repositoryURI" ascending:YES];
        self.baseSources = [[sources allObjects] sortedArrayUsingDescriptors:@[sortDescriptor]];
    }
    
    return self;
}

#pragma mark - View Controller Lifecycle

- (void)loadView {
    [super loadView];

    self.navigationController.navigationBar.navProgressView.progress = 0;
    
    if (self.navigationController.viewControllers.firstObject == self) {
        UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
        self.navigationItem.leftBarButtonItem = cancelItem;
    }
    
    UIBarButtonItem *importItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Import", @"") style:UIBarButtonItemStyleDone target:self action:@selector(importSelected)];
    importItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = importItem;
    
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBSourceTableViewCell" bundle:nil] forCellReuseIdentifier:@"sourceTableViewCell"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (!baseSources || !baseSources.count) {
        [self processSourcesFromLists];
        
        self.navigationItem.title = NSLocalizedString(@"Import Sources", @"");
            
        [self.tableView reloadData];
    } else {
        sourcesToVerify = baseSources.count;
        individualIncrement = (double) 1 / sourcesToVerify;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            for (ZBBaseSource *source in self->baseSources) {
                self->titles[[source uuid]] = NSLocalizedString(@"Verifying...", @"");
            }
            
            [self->sourceManager verifySources:[NSSet setWithArray:self->baseSources] delegate:self];
        });
    }
}

- (void)increaseProgressBy:(double)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        double trueProgress = self.navigationController.navigationBar.navProgressView.progress + progress;
        if (trueProgress >= 1.0) {
            [self.navigationController.navigationBar.navProgressView setProgress:1.0 animated:YES];
            [UIView animateWithDuration:0.5 animations:^{
                [self.navigationController.navigationBar.navProgressView setAlpha:0.0];
            } completion:^(BOOL finished) {
                [self setImportEnabled:[self shouldEnableImportButton]];
            }];
        }
        else {
            [self.navigationController.navigationBar.navProgressView setProgress:trueProgress animated:YES];
        }
    });
}

- (void)setImportEnabled:(BOOL)enabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navigationItem.rightBarButtonItem.enabled = enabled;
    });
}

- (BOOL)shouldEnableImportButton {
    for (NSString *bfn in selectedSources) {
        if ([selectedSources[bfn] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return baseSources.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (baseSources.count) {
        ZBSourceTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sourceTableViewCell"];
        if (!cell) {
            cell = (ZBSourceTableViewCell *)[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sourceTableViewCell"];
        }
        
        ZBBaseSource *source = baseSources[indexPath.row];
        ZBSourceVerificationStatus status = source.verificationStatus;
        
        cell.sourceLabel.alpha = 1.0;
        cell.urlLabel.alpha = 1.0;
        cell.sourceLabel.textColor = [UIColor primaryTextColor];
        [cell setSpinning:NO];
        switch (status) {
            case ZBSourceExists: {
                BOOL selected = [selectedSources[[source uuid]] boolValue];
                cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
                break;
            }
            case ZBSourceUnverified: {
                [cell setSpinning:YES];
                cell.accessoryType = UITableViewCellAccessoryNone;
                
                cell.sourceLabel.alpha = 0.7;
                cell.urlLabel.alpha = 0.7;
                break;
            }
            case ZBSourceImaginary: {
                cell.accessoryType = UITableViewCellAccessoryNone;
                
                cell.sourceLabel.textColor = [UIColor systemPinkColor];
                break;
            }
            case ZBSourceVerifying: {
                [cell setSpinning:YES];
                
                cell.sourceLabel.alpha = 0.7;
                cell.urlLabel.alpha = 0.7;
                break;
            }
        }
        
        cell.sourceLabel.text = self.titles[[source uuid]];
        cell.urlLabel.text = source.repositoryURI;
        
        [cell.iconImageView sd_setImageWithURL:[[source mainDirectoryURL] URLByAppendingPathComponent:@"CydiaIcon.png"] placeholderImage:[UIImage imageNamed:@"Unknown"]];
        
        return cell;
    }
    else {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noSourcesCell"];
        
        cell.textLabel.text = NSLocalizedString(@"No sources to import", @"");
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor secondaryTextColor];
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!baseSources.count) return;
    
    ZBBaseSource *source = baseSources[indexPath.row];
    if (source && source.verificationStatus == ZBSourceExists) {
        BOOL selected = [selectedSources[[source uuid]] boolValue];
        
        [self setSource:source selected:!selected];
        [self updateCellForSource:source];
        [self setImportEnabled:[self shouldEnableImportButton]];
    }
}

- (void)updateCellForSource:(ZBBaseSource *)source {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger index = [self->baseSources indexOfObject:source];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
        
        [self.tableView beginUpdates];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView endUpdates];
    });
}

#pragma mark - Processing Sources

- (void)processSourcesFromLists {
    NSMutableSet *baseSourcesSet = [NSMutableSet new];

    for (NSURL *sourcesLocation in sourceFilesToImport) {
        NSError *error = nil;
        [baseSourcesSet unionSet:[ZBBaseSource baseSourcesFromList:sourcesLocation error:&error]];
        
        if (error) {
            break;
        }
    }
    
    [baseSourcesSet minusSet:[ZBBaseSource baseSourcesFromList:[ZBAppDelegate sourcesListURL] error:nil]];

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"repositoryURI" ascending:YES];
    baseSources = [[baseSourcesSet allObjects] sortedArrayUsingDescriptors:@[sortDescriptor]];
    
    sourcesToVerify = baseSources.count;
    individualIncrement = (double) 1 / sourcesToVerify;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        for (ZBBaseSource *source in self->baseSources) {
            self->titles[[source uuid]] = NSLocalizedString(@"Verifying...", @"");
        }
        
        [self->sourceManager verifySources:[NSSet setWithArray:self->baseSources] delegate:self];
    });
}

#pragma mark - Importing Sources

- (void)setSource:(ZBBaseSource *)source selected:(BOOL)selected {
    if (source.verificationStatus != ZBSourceExists) return;
    
    self.selectedSources[[source uuid]] = @(selected);
}

- (void)importSelected {
    NSMutableSet *sources = [NSMutableSet new];
    NSMutableArray *baseFilenames = [NSMutableArray new];
    
    for (NSString *baseFilename in [self.selectedSources allKeys]) {
        if ([self.selectedSources[baseFilename] boolValue]) {
            if (baseFilename) [baseFilenames addObject:baseFilename];
        }
    }
    
    for (ZBBaseSource *source in self->baseSources) {
        if ([baseFilenames containsObject:[source uuid]]) {
            if (source) [sources addObject:source];
        }
    }
    
    NSString *message = sources.count > 1 ? [NSString stringWithFormat:NSLocalizedString(@"Are you sure that you want to import %d sources into Zebra?", @""), (int)sources.count] : NSLocalizedString(@"Are you sure that you want to import 1 source into Zebra?", @"");
    UIAlertController *areYouSure = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm Import", @"") message:message preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self->sourceManager addSources:sources error:nil];
        
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    [areYouSure addAction:yesAction];
    
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:nil];
    [areYouSure addAction:noAction];
    
    areYouSure.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:areYouSure animated:YES completion:nil];
}

#pragma mark - Verification Delegate

- (void)source:(ZBBaseSource *)source status:(ZBSourceVerificationStatus)status {
    if (status == ZBSourceExists) {
        [source getLabel:^(NSString * _Nonnull label) {
            if (!label) {
                label = source.repositoryURI;
            }
            
            self->titles[[source uuid]] = label;
            [self setSource:source selected:YES];
            [self updateCellForSource:source];
            
            [self increaseProgressBy:self->individualIncrement];
        }];
    }
    else if (status == ZBSourceImaginary) {
        self->titles[[source uuid]] = NSLocalizedString(@"Unable to verify source", @"");
        [self updateCellForSource:source];
        
        [self increaseProgressBy:individualIncrement];
    }
}

@end
