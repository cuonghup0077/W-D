//
//  ZBAppDelegate.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#define IMAGE_CACHE_MAX_TIME 60 * 60 * 24 // 1 Day

#import "ZBAppDelegate.h"

#import <UI/ZBTabBarController.h>
#import <UI/ZBLoadingViewController.h>

#import <Plains/Plains.h>

#import <ZBLog.h>
#import <UI/ZBTab.h>
#import <ZBDevice.h>
#import <ZBSettings.h>
#import <Notifications/ZBNotificationManager.h>
#import <Extensions/ZBColor.h>
#import <UI/Sources/ZBSourceListViewController.h>
#import <UI/Packages/ZBPackageViewController.h>
#import <UI/Search/ZBSearchViewController.h>
#import <UI/Sources/ZBSourceViewController.h>
#import <UI/Sources/ZBSourceImportViewController.h>
#import <UI/ZBSidebarController.h>
#import <dlfcn.h>
#include <sys/stat.h>
//#import <objc/runtime.h>
#import <Headers/AccessibilityUtilities.h>

#import <SDWebImage/SDWebImage.h>

@interface ZBAppDelegate () {
    NSString *forwardToPackageID;
    BOOL screenRecording;
    PLConfig *config;
}

@property () UIBackgroundTaskIdentifier backgroundTask;

@end

@implementation ZBAppDelegate

NSString *const ZBUserWillTakeScreenshotNotification = @"WillTakeScreenshotNotification";
NSString *const ZBUserDidTakeScreenshotNotification = @"DidTakeScreenshotNotification";

NSString *const ZBUserStartedScreenCaptureNotification = @"StartedScreenCaptureNotification";
NSString *const ZBUserEndedScreenCaptureNotification = @"EndedScreenCaptureNotification";

+ (NSString *)bundleID {
    return [[NSBundle mainBundle] bundleIdentifier];
}

+ (NSString *)homeDirectory {
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    return NSHomeDirectory();
#else
    return @"/var/mobile";
#endif
}

+ (NSString *)slingshotPath {
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
    return [NSString stringWithFormat:@"/opt/procursus/libexec/%@/supersling", LIBEXEC_FOLDER];
#else
    return [NSString stringWithFormat:@"/usr/libexec/%@/supersling", LIBEXEC_FOLDER];
#endif
}

+ (NSString *)cacheDirectory {
    return [NSString stringWithFormat:@"%@/Library/Caches/%@", [self homeDirectory], [[NSBundle mainBundle] bundleIdentifier]];
}

//+ (NSString *)documentsDirectory {
//    NSString *path_ = nil;
//    if (![ZBDevice needsSimulation]) {
//        path_ = @"/var/mobile/Library/Application Support";
//    } else {
//        path_ = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
//    }
//    NSString *path = [path_ stringByAppendingPathComponent:[self bundleID]];
//    BOOL dirExists = NO;
//    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dirExists];
//    if (!dirExists) {
//        ZBLog(@"[Zebra] Creating documents directory.");
//        NSError *error = NULL;
//        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
//        
//        if (error != NULL) {
//            [self sendErrorToTabController:[NSString stringWithFormat:NSLocalizedString(@"Error while creating documents directory: %@.", @""), error.localizedDescription]];
//            NSLog(@"[Zebra] Error while creating documents directory: %@.", error.localizedDescription);
//        }
//    }
//    
//    return path;
//}
//
//+ (NSURL *)documentsDirectoryURL {
//    return [NSURL URLWithString:[[NSString stringWithFormat:@"filza://view%@", [self documentsDirectory]] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
//}
//
//+ (NSString *)listsLocation {
//    NSString *lists = [[self documentsDirectory] stringByAppendingPathComponent:@"/lists/"];
//    BOOL dirExists = NO;
//    [[NSFileManager defaultManager] fileExistsAtPath:lists isDirectory:&dirExists];
//    if (!dirExists) {
//        ZBLog(@"[Zebra] Creating lists directory.");
//        NSError *error = NULL;
//        [[NSFileManager defaultManager] createDirectoryAtPath:lists withIntermediateDirectories:YES attributes:nil error:&error];
//        
//        if (error != NULL) {
//            [self sendErrorToTabController:[NSString stringWithFormat:NSLocalizedString(@"Error while creating lists directory: %@.", @""), error.localizedDescription]];
//            NSLog(@"[Zebra] Error while creating lists directory: %@.", error.localizedDescription);
//        }
//    }
//    return lists;
//}
//
//+ (NSURL *)sourcesListURL {
//    return [NSURL fileURLWithPath:[self sourcesListPath]];
//}
//
//+ (NSString *)sourcesListPath {
//    return [[PLConfig sharedInstance] stringForKey:@"Plains::SourcesList"];
//}
//
//+ (NSString *)databaseLocation {
//    return [[self documentsDirectory] stringByAppendingPathComponent:@"zebra.db"];
//}
//
//+ (NSString *)debsLocation {
//    NSString *debs = [[self documentsDirectory] stringByAppendingPathComponent:@"/debs/"];
//    BOOL dirExists = NO;
//    [[NSFileManager defaultManager] fileExistsAtPath:debs isDirectory:&dirExists];
//    if (!dirExists) {
//        ZBLog(@"[Zebra] Creating debs directory.");
//        NSError *error = NULL;
//        [[NSFileManager defaultManager] createDirectoryAtPath:debs withIntermediateDirectories:YES attributes:nil error:&error];
//        
//        if (error != NULL) {
//            [self sendErrorToTabController:[NSString stringWithFormat:NSLocalizedString(@"Error while creating debs directory: %@.", @""), error.localizedDescription]];
//            NSLog(@"[Zebra] Error while creating debs directory: %@.", error.localizedDescription);
//        }
//    }
//    return debs;
//}

+ (ZBTabBarController *)tabBarController {
    if ([NSThread isMainThread]) {
        return (ZBTabBarController *)((ZBAppDelegate *)[[UIApplication sharedApplication] delegate]).window.rootViewController;
    }
    else {
        __block ZBTabBarController *tabController;
        dispatch_sync(dispatch_get_main_queue(), ^{
            tabController = (ZBTabBarController *)((ZBAppDelegate *)[[UIApplication sharedApplication] delegate]).window.rootViewController;
        });
        return tabController;
    }
}

+ (void)sendAlertFrom:(UIViewController *)vc title:(NSString *)title message:(NSString *)message actionLabel:(NSString *)actionLabel okLabel:(NSString *)okLabel block:(void (^)(void))block {
    UIViewController *trueVC = vc ? vc : [self tabBarController];
    if (trueVC != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            
            if (actionLabel != nil && block != NULL) {
                UIAlertAction *blockAction = [UIAlertAction actionWithTitle:actionLabel style:UIAlertActionStyleDefault handler:^(UIAlertAction *action_) {
                    block();
                }];
                [alert addAction:blockAction];
            }
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:okLabel style:UIAlertActionStyleCancel handler:nil];
            [alert addAction:okAction];
            [trueVC presentViewController:alert animated:YES completion:nil];
        });
    }
}

+ (void)sendAlertFrom:(UIViewController *)vc message:(NSString *)message {
    [self sendAlertFrom:vc title:@"Zebra" message:message actionLabel:nil okLabel:NSLocalizedString(@"Ok", @"") block:NULL];
}

+ (void)sendErrorToTabController:(NSString *)error actionLabel:(NSString *)actionLabel block:(void (^)(void))block {
    [self sendAlertFrom:nil title:NSLocalizedString(@"An Error Occurred", @"") message:error actionLabel:actionLabel okLabel:NSLocalizedString(@"Dismiss", @"") block:block];
}

+ (void)sendErrorToTabController:(NSString *)error {
    [self sendErrorToTabController:error actionLabel:nil block:NULL];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    if (@available(iOS 13.0, macCatalyst 13.0, *)) {
        if (![ZBSettings usesSystemAppearance]) {
            ZBInterfaceStyle style = [ZBSettings interfaceStyle];
            if (style == ZBInterfaceStyleLight) {
                self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
            } else {
                self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            }
        }
    }
    
#if TARGET_OS_MACCATALYST
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"main"];
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    
    UITitlebar *titlebar = self.window.windowScene.titlebar;
    titlebar.toolbar = toolbar;
    titlebar.toolbarStyle = UITitlebarToolbarStyleAutomatic;
#endif
    
    [self setupPlains];
    [self registerForScreenshotNotifications];
    [self setupSDWebImageCache];
//    [[ZBNotificationManager sharedInstance] ensureNotificationAccess];
    
    self.window.rootViewController = [[ZBLoadingViewController alloc] init];
    [self.window makeKeyAndVisible];
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [[PLPackageManager sharedInstance] import];
        
        dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_MACCATALYST
            [self setupSidebar];
#else
            if (self.window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
                [self setupTabBar];
            } else {
                [self setupSidebar];
            }
#endif
            UIViewController *rvc = self.window.rootViewController;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            [rvc performSelector:@selector(requestSourceRefresh)];
#pragma cland diagnostic pop
        });
    });
    
    return YES;
}

- (void)setupSidebar {
    if (@available(macCatalyst 14.0, iOS 14.0, *)) {
        ZBSidebarController *sidebar = [[ZBSidebarController alloc] init];
        
#if TARGET_OS_MACCATALYST
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"main"];
        toolbar.delegate = sidebar;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        
        UITitlebar *titlebar = self.window.windowScene.titlebar;
        titlebar.toolbar = toolbar;
        titlebar.toolbarStyle = UITitlebarToolbarStyleAutomatic;
#endif
        
        self.window.rootViewController = sidebar;
    } else {
        [self setupTabBar];
    }
    
    UIDropInteraction *dropInteraction = [[UIDropInteraction alloc] initWithDelegate:self];
    [self.window addInteraction:dropInteraction];
}

- (void)setupTabBar {
    ZBTabBarController *tabBar = [[ZBTabBarController alloc] init];
    
    self.window.rootViewController = tabBar;
}

- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    NSArray *identifiers = @[@"org.debian.deb-archive", @"org.debian.sources-list", @"org.debian.sources-file"];
    return [session hasItemsConformingToTypeIdentifiers:identifiers] && session.items.count == 1;
}

- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction sessionDidUpdate:(id<UIDropSession>)session {
    return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationCopy];
}

- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    UIDragItem *item = session.items.firstObject; // This can be modified to support more than one item but for now I'm leaving it with just one
    if ([item.itemProvider hasItemConformingToTypeIdentifier:@"org.debian.sources-list"]) {
        [item.itemProvider loadItemForTypeIdentifier:@"org.debian.sources-list" options:nil completionHandler:^(__kindof id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
            [self handleSourceImport:(NSURL *)item];
        }];
    } else if ([item.itemProvider hasItemConformingToTypeIdentifier:@"org.debian.sources-file"]) {
        [item.itemProvider loadItemForTypeIdentifier:@"org.debian.sources-group" options:nil completionHandler:^(__kindof id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
            [self handleSourceImport:(NSURL *)item];
        }];
    } else if ([item.itemProvider hasItemConformingToTypeIdentifier:@"org.debian.deb-archive"]) {
        [item.itemProvider loadItemForTypeIdentifier:@"org.debian.deb-archive" options:nil completionHandler:^(__kindof id<NSSecureCoding>  _Nullable item, NSError * _Null_unspecified error) {
            [[PLQueue sharedInstance] queueLocalPackage:(NSURL *)item];
        }];
    }
}

- (void)handleSourceImport:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        ZBSourceImportViewController *importVC = [[ZBSourceImportViewController alloc] initWithPaths:@[url]];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:importVC];
        
        [self.window.rootViewController presentViewController:nav animated:YES completion:nil];
    });
}

- (BOOL)application:(UIApplication *)application openURL:(nonnull NSURL *)url options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    NSArray *choices = @[@"file", @"zbra"];
    int index = (int)[choices indexOfObject:[url scheme]];

//    if (![self.window.rootViewController isKindOfClass:[ZBTabBarController class]]) {
//        return NO;
//    }

    switch (index) {
        case 0: { // file
            if ([[url pathExtension] isEqualToString:@"deb"]) {
                [[PLQueue sharedInstance] queueLocalPackage:url];
            }
            
            if ([[url pathExtension] isEqualToString:@"list"] || [[url pathExtension] isEqualToString:@"sources"]) {
                [self handleSourceImport:url];
            }
            break;
        }
        case 1: { // zbra
            ZBTabBarController *tabController = (ZBTabBarController *)self.window.rootViewController;

            NSArray *components = [[url host] componentsSeparatedByString:@"/"];
            choices = @[@"home", @"sources", @"changes", @"packages", @"search"];
            index = (int)[choices indexOfObject:components[0]];

            switch (index) {
                case 0: {
                    [tabController setSelectedIndex:ZBTabHome];
                    break;
                }
                case 1: {
                    [tabController setSelectedIndex:ZBTabSources];

//                    ZBSourceListViewController *sourceListController = (ZBSourceListViewController *)((UINavigationController *)[tabController selectedViewController]).viewControllers[0];

//                    [sourceListController handleURL:url];
                    break;
                }
                case 2: {
//                    [tabController setSelectedIndex:ZBTabChanges];
                    break;
                }
//                case 3: {
//                    NSString *path = [url path];
//                    if (path.length > 1) {
//                        NSString *sourceURL = [[url query] componentsSeparatedByString:@"source="][1];
//                        if (sourceURL != NULL) {
//                            if ([ZBSource exists:sourceURL]) {
//                                NSString *packageID = [path substringFromIndex:1];
//                                ZBSource *source = [ZBSource sourceFromBaseURL:sourceURL];
//                                ZBPackage *package = [[ZBDatabaseManager sharedInstance] topVersionForPackageID:packageID inSource:source];
//
//                                if (package) {
//                                    ZBPackageViewController *packageController = [[ZBPackageViewController alloc] initWithPackage:package];
//                                    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:packageController];
//                                    [tabController presentViewController:navController animated:YES completion:nil];
//                                }
//                                else {
//                                    [ZBAppDelegate sendErrorToTabController:[NSString stringWithFormat:NSLocalizedString(@"Could not locate %@ from %@", @""), packageID, [source origin]]];
//                                }
//                            }
//                            else {
//                                NSString *packageID = [path substringFromIndex:1];
//                                [tabController setForwardToPackageID:packageID];
//                                [tabController setForwardedSourceBaseURL:sourceURL];
//
//                                NSURL *newURL = [NSURL URLWithString:[NSString stringWithFormat:@"zbra://sources/add/%@", sourceURL]];
//                                [self application:application openURL:newURL options:options];
//                            }
//                        }
//                        else {
//                            NSString *packageID = [path substringFromIndex:1];
//                            ZBPackage *package = [[ZBDatabaseManager sharedInstance] topVersionForPackageID:packageID];
//                            if (package) {
//                                ZBPackageViewController *packageController = [[ZBPackageViewController alloc] initWithPackage:package];
//                                UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:packageController];
//                                [tabController presentViewController:navController animated:YES completion:nil];
//                            }
//                            else {
//                                [ZBAppDelegate sendErrorToTabController:[NSString stringWithFormat:NSLocalizedString(@"Could not locate %@", @""), packageID]];
//                            }
//                        }
//                    }
//                    else {
//                        [tabController setSelectedIndex:ZBTabPackages];
//                    }
//                    break;
//                }
                case 4: {
                    [tabController setSelectedIndex:ZBTabSearch];

                    ZBSearchViewController *searchController = (ZBSearchViewController *)((UINavigationController *)[tabController selectedViewController]).viewControllers[0];
                    [searchController handleURL:url];
                    break;
                }
            }
            break;
        }
        default: {
            return NO;
        }
    }

    return YES;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler {
    if (![self.window.rootViewController isKindOfClass:[ZBTabBarController class]]) {
        return;
    }
    
    ZBTabBarController *tabController = (ZBTabBarController *)self.window.rootViewController;
    if ([shortcutItem.type isEqualToString:@"Search"]) {
        [tabController setSelectedIndex:ZBTabSearch];
        
        ZBSearchViewController *searchController = (ZBSearchViewController *)((UINavigationController *)[tabController selectedViewController]).viewControllers[0];
        [searchController handleURL:nil];
    } else if ([shortcutItem.type isEqualToString:@"Add"]) {
        [tabController setSelectedIndex:ZBTabSources];
        
//        ZBSourceListViewController *sourceListController = (ZBSourceListViewController *)((UINavigationController *)[tabController selectedViewController]).viewControllers[0];
        
//        [sourceListController handleURL:[NSURL URLWithString:@"zbra://sources/add"]];
    } else if ([shortcutItem.type isEqualToString:@"Refresh"]) {
        ZBTabBarController *tabController = [ZBAppDelegate tabBarController];
        
        [tabController refreshSources:YES];
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(BackgroundCompletionHandler)completionHandler {
    NSDate *fetchStart = [NSDate date];
    NSLog(@"[Zebra] Background fetch started");

    self.backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"[Zebra] WARNING: Background refresh timed out");
        [application endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
        completionHandler(UIBackgroundFetchResultFailed);
    }];

//    [[ZBNotificationManager sharedInstance] performBackgroundFetch:^(UIBackgroundFetchResult result) {
//        NSTimeInterval fetchDuration = [[NSDate date] timeIntervalSinceDate:fetchStart];
//        NSLog(@"[Zebra] Background refresh finished in %f seconds", fetchDuration);
//        [application endBackgroundTask:self.backgroundTask];
//        self.backgroundTask = UIBackgroundTaskInvalid;
//        
//        // Hard-coded "NewData" for (hopefully) better fetch intervals
//        completionHandler(UIBackgroundFetchResultNewData);
//    }];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)setupPlains {
    config = [PLConfig sharedInstance];
    
    int filedes[2];
    if (pipe(filedes) == -1) {
        NSLog(@"[Zebra] Unable to create file descriptors.");
    } else {
        [config setInteger:filedes[0] forKey:@"Plains::FinishFD::"];
        [config setInteger:filedes[1] forKey:@"Plains::FinishFD::"]; 
    }
    
    // Create directories
    NSString *slingshotPath = [ZBAppDelegate slingshotPath];
    NSString *cacheDir = [ZBAppDelegate cacheDirectory];
#if TARGET_OS_SIMULATOR
    NSUInteger libraryIndex1 = [cacheDir rangeOfString:@"/Library/Developer"].location;
    NSUInteger libraryIndex2 = [cacheDir rangeOfString:@"/Library/Caches"].location;
    cacheDir = [cacheDir stringByReplacingCharactersInRange:NSMakeRange(libraryIndex1, libraryIndex2 - libraryIndex1) withString:@""];
#endif
    NSString *logDir = [NSString stringWithFormat:@"%@/logs", cacheDir];
    NSString *listDir = [NSString stringWithFormat:@"%@/lists", cacheDir];
    NSString *archiveDir = [NSString stringWithFormat:@"%@/archives/partial", cacheDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:NO attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:NO attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:listDir withIntermediateDirectories:NO attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:archiveDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Shared Options
    [config setBoolean:YES forKey:@"Acquire::AllowInsecureRepositories"];
    [config setString:logDir forKey:@"Dir::Log"];
    [config setString:listDir forKey:@"Dir::State::Lists"];
    [config setString:cacheDir forKey:@"Dir::Cache"];
    [config setString:[cacheDir stringByAppendingPathComponent:@"zebra.sources"] forKey:@"Plains::SourcesList"];
    [config setString:slingshotPath forKey:@"Dir::Bin::dpkg"];
    [config setString:slingshotPath forKey:@"Plains::Slingshot"];
#if TARGET_OS_MACCATALYST
    [config setString:[NSString stringWithFormat:@"Zebra %@; macOS %@", PACKAGE_VERSION, [[UIDevice currentDevice] systemVersion]] forKey:@"Acquire::http::User-Agent"];
#else
    [config setString:[NSString stringWithFormat:@"Zebra %@; iOS %@", PACKAGE_VERSION, [[UIDevice currentDevice] systemVersion]] forKey:@"Acquire::http::User-Agent"];
#endif
    
    NSString *extendedStatesPath = [@"/" stringByAppendingString:[[config stringForKey:@"Dir::State"] stringByAppendingPathComponent:@"extended_states"]];
    symlink(extendedStatesPath.UTF8String, [cacheDir stringByAppendingPathComponent:@"extended_states"].UTF8String);
    [config setString:cacheDir forKey:@"Dir::State"];
    
    // Reset the default compression type ordering
    [config setString:@"zstd" forKey:@"Acquire::CompressionTypes::zst"];
    [config setString:@"xz" forKey:@"Acquire::CompressionTypes::xz"];
    [config setString:@"lzma" forKey:@"Acquire::CompressionTypes::lzma"];
    [config setString:@"lz4" forKey:@"Acquire::CompressionTypes::lz4"];
    [config setString:@"gzip" forKey:@"Acquire::CompressionTypes::gz"];
    [config setString:@"bzip2" forKey:@"Acquire::CompressionTypes::bz2"];
#if DEBUG
//    _config->Set("Debug::pkgProblemResolver", true);
//    _config->Set("Debug::pkgAcquire", true);
//    _config->Set("Debug::pkgAcquire::Worker", true);
#endif
}

- (void)setupSDWebImageCache {
    [SDImageCache sharedImageCache].config.maxDiskAge = IMAGE_CACHE_MAX_TIME; // Sets SDWebImage to cache for 1 day.
}

- (void)registerForScreenshotNotifications {
//    dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
//    AXSpringBoardServer *server = [objc_getClass("AXSpringBoardServer") server];
//    [server registerSpringBoardActionHandler:^(int eventType) {
//        if (eventType == 6) { // Before taking screenshot
//            [[NSNotificationCenter defaultCenter] postNotificationName:ZBUserWillTakeScreenshotNotification object:nil];
//        }
//        else if (eventType == 7) { // After taking screenshot
//            [[NSNotificationCenter defaultCenter] postNotificationName:ZBUserDidTakeScreenshotNotification object:nil];
//        }
//    } withIdentifierCallback:^(int a) {}];
    
//    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkForScreenRecording:) name:UIScreenCapturedDidChangeNotification object:nil];
}

- (void)checkForScreenRecording:(NSNotification *)notif {
    UIScreen *screen = [notif object];
    if (!screen) return;
    
    if ([screen isCaptured] || [screen mirroredScreen]) {
        screenRecording = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:ZBUserStartedScreenCaptureNotification object:nil];
    }
    else if (screenRecording) {
        screenRecording = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:ZBUserEndedScreenCaptureNotification object:nil];
    }
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UINavigationController *)navigationController {
    static UITableViewController *previousController = nil;
    UITableViewController *currentController = [navigationController viewControllers][0];
    if (previousController == currentController) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wundeclared-selector"

        if ([currentController respondsToSelector:@selector(scrollToTop)]) {
            [currentController performSelector:@selector(scrollToTop)];
        }

        #pragma clang diagnostic pop
    }
    previousController = [navigationController viewControllers][0]; // Should set the previousController to the rootVC
}

@end
