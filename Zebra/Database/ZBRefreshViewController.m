//
//  ZBRefreshViewController.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#import <ZBTabBarController.h>
#import <ZBDevice.h>
#import <ZBAppDelegate.h>
#import <Database/ZBDatabaseManager.h>
#import <Downloads/ZBDownloadManager.h>
#import <ZBRepoManager.h>
#include <Parsel/parsel.h>
#import "ZBRefreshViewController.h"

typedef enum {
    ZBStateCancel = 0,
    ZBStateDone
} ZBRefreshButtonState;

@interface ZBRefreshViewController () {
    ZBDatabaseManager *databaseManager;
    BOOL hadAProblem;
    ZBRefreshButtonState buttonState;
}
@property (strong, nonatomic) IBOutlet UIButton *completeOrCancelButton;
@property (strong, nonatomic) IBOutlet UITextView *consoleView;
@end

@implementation ZBRefreshViewController

@synthesize messages;
@synthesize completeOrCancelButton;
@synthesize consoleView;

- (id)init {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self = [storyboard instantiateViewControllerWithIdentifier:@"refreshController"];
    
    if (self) {
        self.messages = NULL;
        self.dropTables = NO;
        self.repoURLs = NULL;
    }
    
    return self;
}

- (id)initWithMessages:(NSArray *)messages {
    self = [self init];
    
    if (self) {
        self.messages = messages;
    }
    
    return self;
}

- (id)initWithDropTables:(BOOL)dropTables {
    self = [self init];
    
    if (self) {
        self.dropTables = dropTables;
    }
    
    return self;
}

- (id)initWithRepoURLs:(NSArray *)repoURLs {
    self = [self init];
    
    if (self) {
        self.repoURLs = repoURLs;
    }
    
    return self;
}

- (id)initWithMessages:(NSArray *)messages dropTables:(BOOL)dropTables {
    self = [self init];
    
    if (self) {
        self.messages = messages;
        self.dropTables = dropTables;
    }
    
    return self;
}

- (id)initWithMessages:(NSArray *)messages repoURLs:(NSArray *)repoURLs {
    self = [self init];
    
    if (self) {
        self.messages = messages;
        self.repoURLs = repoURLs;
    }
    
    return self;
}

- (id)initWithDropTables:(BOOL)dropTables repoURLs:(NSArray *)repoURLs {
    self = [self init];
    
    if (self) {
        self.dropTables = dropTables;
        self.repoURLs = repoURLs;
    }
    
    return self;
}

- (id)initWithMessages:(NSArray *)messages dropTables:(BOOL)dropTables repoURLs:(NSArray *)repoURLs {
    self = [self init];
    
    if (self) {
        self.messages = messages;
        self.dropTables = dropTables;
        self.repoURLs = repoURLs;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_dropTables) {
        [self setCompleteOrCancelButtonHidden:YES];
    } else {
        [self updateCompleteOrCancelButtonText:NSLocalizedString(@"Cancel", @"")];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(disableCancelButton) name:@"disableCancelRefresh" object:nil];
    if ([ZBDevice darkModeEnabled]) {
        [self setNeedsStatusBarAppearanceUpdate];
        [self.view setBackgroundColor:[UIColor tableViewBackgroundColor]];
        [consoleView setBackgroundColor:[UIColor tableViewBackgroundColor]];
    }
}

- (void)disableCancelButton {
    buttonState = ZBStateDone;
    [self setCompleteOrCancelButtonHidden:YES];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return [ZBDevice darkModeEnabled] ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (!messages) {
        databaseManager = [ZBDatabaseManager sharedInstance];
        [databaseManager addDatabaseDelegate:self];
        
        if (_dropTables) {
            [databaseManager dropTables];
        }
        
        if (self.repoURLs.count) {
            // Update only the repos specified
            [databaseManager updateRepoURLs:self.repoURLs useCaching:NO];
        } else {
            // Update every repo
            [databaseManager updateDatabaseUsingCaching:NO userRequested:YES];
        }
    } else {
        hadAProblem = YES;
        for (NSString *message in messages) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self writeToConsole:message atLevel:ZBLogLevelError];
            });
        }
        [consoleView setNeedsLayout];
        buttonState = ZBStateDone;
        [self clearProblems];
    }
}

- (IBAction)completeOrCancelButton:(id)sender {
    if (buttonState == ZBStateDone) {
        [self goodbye];
    }
    else {
        if (_dropTables) {
            return;
        }
        [databaseManager cancelUpdates:self];
        [((ZBTabBarController *)self.tabBarController) clearRepos];
        [self writeToConsole:@"Refresh cancelled\n" atLevel:ZBLogLevelInfo]; // TODO: localization
        
        buttonState = ZBStateDone;
        [self updateCompleteOrCancelButtonText:NSLocalizedString(@"Done", @"")];
    }
}

- (void)clearProblems {
    messages = NULL;
    hadAProblem = NO;
    [self clearConsoleText];
}

- (void)goodbye {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(goodbye) withObject:nil waitUntilDone:NO];
    } else {
        [self clearProblems];
        ZBTabBarController *controller = (ZBTabBarController *)[self presentingViewController];
        [self dismissViewControllerAnimated:YES completion:^{
            if ([controller isKindOfClass:[ZBTabBarController class]]) {
                [controller forwardToPackage];
            }
        }];
    }
}

#pragma mark - UI Updates

- (void)setCompleteOrCancelButtonHidden:(BOOL)hidden {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->completeOrCancelButton setHidden:hidden];
    });
}

- (void)updateCompleteOrCancelButtonText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.completeOrCancelButton setTitle:text forState:UIControlStateNormal];
    });
}

- (void)clearConsoleText {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->consoleView setText:nil];
    });
}

- (void)writeToConsole:(NSString *)str atLevel:(ZBLogLevel)level {
    if (str == NULL)
        return;
    if (![str hasSuffix:@"\n"])
        str = [str stringByAppendingString:@"\n"];
    __block BOOL isDark = [ZBDevice darkModeEnabled];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIColor *color = [UIColor whiteColor];
        UIFont *font;
        switch (level) {
            case ZBLogLevelDescript ... ZBLogLevelInfo: {
                if (!isDark) {
                    color = [UIColor blackColor];
                }
                font = [UIFont fontWithName:level == ZBLogLevelDescript ? @"CourierNewPSMT" : @"CourierNewPS-BoldMT" size:10.0];
                break;
            }
            case ZBLogLevelError: {
                color = [UIColor redColor];
                font = [UIFont fontWithName:@"CourierNewPS-BoldMT" size:10.0];
                break;
            }
            case ZBLogLevelWarning: {
                color = [UIColor yellowColor];
                font = [UIFont fontWithName:@"CourierNewPSMT" size:10.0];
                break;
            }
            default:
                break;

        }

        NSDictionary *attrs = @{ NSForegroundColorAttributeName: color, NSFontAttributeName: font };
        
        [self->consoleView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:str attributes:attrs]];

        if (self->consoleView.text.length) {
            NSRange bottom = NSMakeRange(self->consoleView.text.length -1, 1);
            [self->consoleView scrollRangeToVisible:bottom];
        }
    });
}


#pragma mark - Database Delegate

- (void)databaseStartedUpdate {
    hadAProblem = NO;
}

- (void)databaseCompletedUpdate:(int)packageUpdates {
    ZBTabBarController *tabController = [ZBAppDelegate tabBarController];
    if (packageUpdates != -1) {
        [tabController setPackageUpdateBadgeValue:packageUpdates];
    }
    if (!hadAProblem) {
        [self goodbye];
    } else {
        [self setCompleteOrCancelButtonHidden:NO];
        [self updateCompleteOrCancelButtonText:NSLocalizedString(@"Done", @"")];
    }
    [[ZBRepoManager sharedInstance] needRecaching];
}

- (void)postStatusUpdate:(NSString *)status atLevel:(ZBLogLevel)level {
    if (level == ZBLogLevelError || level == ZBLogLevelWarning) {
        hadAProblem = YES;
    }
    [self writeToConsole:status atLevel:level];
}

@end
