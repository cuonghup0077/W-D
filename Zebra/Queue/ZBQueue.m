//
//  ZBQueue.m
//  Zebra
//
//  Created by Wilson Styres on 1/29/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBQueue.h"
#import <Packages/Helpers/ZBPackage.h>
#import <Packages/Helpers/ZBPackageActionsManager.h>
#import <ZBAppDelegate.h>
#import <Database/ZBDependencyResolver.h>
#import <Database/ZBDatabaseManager.h>
#import <ZBDevice.h>
#import <Console/ZBStage.h>

@interface ZBQueue ()
@property (nonatomic, strong) NSMutableArray<NSString *> *queuedPackagesList;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray <ZBPackage *> *> *managedQueue;
@end

@implementation ZBQueue

@synthesize managedQueue;
@synthesize queuedPackagesList;
@synthesize removingZebra;
@synthesize zebraPath;

+ (id)sharedQueue {
    static ZBQueue *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ZBQueue new];
    });
    return instance;
}

+ (int)count {
    int numberOfPackages = 0;
    for (NSArray *queue in [[self sharedQueue] queues]) {
        numberOfPackages += [queue count];
    }
    numberOfPackages += [[[self sharedQueue] dependencyQueue] count]; //dependencyQueue is not a member of [self queues]
    numberOfPackages += [[[self sharedQueue] conflictQueue] count]; //conflictQueue is not a member of [self queues]
    return numberOfPackages;
}

- (id)init {
    self = [super init];
    
    if (self) {
        managedQueue = [NSMutableDictionary new];
        for (ZBQueueType q = ZBQueueTypeInstall; q <= ZBQueueTypeDependency; q <<= 1) {
            [managedQueue setObject:[NSMutableArray new] forKey:@(q)];
        }
        queuedPackagesList = [NSMutableArray new];
    }
    
    return self;
}

- (void)updateQueueBarData {
    [[ZBAppDelegate tabBarController] updateQueueBar];
}

- (void)addPackage:(ZBPackage *)package toQueue:(ZBQueueType)queue {
    if (package == NULL) return;
    
    ZBQueueType type = [self locate:package];
    if (type != ZBQueueTypeClear && type != queue) { //Remove package from queue
        [self removePackage:package inQueue:type versionStrict:false];
    }
    if (type != queue) {
        [[self queueFromType:queue] addObject:package];
        [queuedPackagesList addObject:[package identifier]];
        if (queue == ZBQueueTypeInstall || queue == ZBQueueTypeUpgrade || queue == ZBQueueTypeDowngrade) {
            NSLog(@"[Zebra] Finding dependencies for %@", package);
            if ([self enqueueDependenciesForPackage:package]) {
                NSLog(@"[Zebra] All dependencies found for %@", package);
            }
            else {
                NSLog(@"[Zebra] Unable to find all dependencies for %@", package);
            }
        }
        else if (queue == ZBQueueTypeRemove) {
            NSLog(@"[Zebra] Removing packages that depend on %@", package);
            [self enqueueRemovalOfPackagesThatDependOn:package];
        }
    }
    [self updateQueueBarData];
}

- (void)addPackages:(NSArray <ZBPackage *> *)packages toQueue:(ZBQueueType)queue {
    for (ZBPackage *package in packages) {
        [self addPackage:package toQueue:queue];;
    }
}

- (void)addDependency:(ZBPackage *)package {
    if (![[self dependencyQueue] containsObject:package]) {
        [queuedPackagesList addObject:[package identifier]];
        for (NSString *providedPackage in [package provides]) {
            NSArray *components = [providedPackage componentsSeparatedByString:@"("];
            NSString *packageID = [components[0] stringByReplacingOccurrencesOfString:@" " withString:@""];
            [queuedPackagesList addObject:packageID];
        }
        
        [[self dependencyQueue] addObject:package];
    }
    [self updateQueueBarData];
}

- (void)addConflict:(ZBPackage *)package {
    [self addConflict:package removeDependencies:true];
}

- (void)addConflict:(ZBPackage *)package removeDependencies:(BOOL)remove {
    ZBQueueType location = [self locate:package];
    if (location != ZBQueueTypeClear) {
        [self removePackage:package inQueue:location];
    }
    if (![[self conflictQueue] containsObject:package]) {
        package.ignoreDependencies = !remove;
        [[self conflictQueue] addObject:package];
        if (remove) [self enqueueRemovalOfPackagesThatDependOn:package];
    }
    [self updateQueueBarData];
}

- (BOOL)enqueueDependenciesForPackage:(ZBPackage *)package {
    ZBDependencyResolver *resolver = [[ZBDependencyResolver alloc] initWithPackage:package];
    return [resolver immediateResolution];
}

- (void)enqueueRemovalOfPackagesThatDependOn:(ZBPackage *)package {
    [self addPackages:[[ZBDatabaseManager sharedInstance] packagesThatDependOn:package] toQueue:ZBQueueTypeRemove];
}

- (void)removePackage:(ZBPackage *)package {
    ZBQueueType action = [self locate:package];
    if (action == ZBQueueTypeRemove) {
        ZBPackage *topPackage = package;
        while ([topPackage removedBy] != NULL) {
            topPackage = [topPackage removedBy];
        }
        [self removePackage:topPackage inQueue:ZBQueueTypeRemove];
        [self removePackagesRemovedBy:topPackage];
    }
    else if (action != ZBQueueTypeClear) {
        [self removePackage:package inQueue:action];
        for (ZBPackage *dependency in [package dependencies]) {
            [[dependency dependencyOf] removeObject:package];
            if ([[dependency dependencyOf] count] <= 1) {
                [self removePackage:dependency];
            }
        }
        for (ZBPackage *dependencyOf in [package dependencyOf]) {
            [[dependencyOf dependencies] removeObject:package];
            [self removePackage:dependencyOf];
        }
    }
    [self updateQueueBarData];
}

- (void)removePackage:(ZBPackage *)package inQueue:(ZBQueueType)queue {
    [[package issues] removeAllObjects];
    [package setRemovedBy:NULL];
    [[self queueFromType:queue] removeObject:package];
    [self updateQueueBarData];
}

- (void)removePackage:(ZBPackage *)package inQueue:(ZBQueueType)queue versionStrict:(BOOL)strict {
    if (!strict) {
        for (ZBPackage *queuedPackage in [self queueFromType:queue]) {
            if ([[package identifier] isEqualToString:[queuedPackage identifier]]) {
                package = queuedPackage;
                break;
            }
        }
    }
    
    [[package issues] removeAllObjects];
    [package setRemovedBy:NULL];
    [[self queueFromType:queue] removeObject:package];
    [self updateQueueBarData];
}

- (void)removePackagesRemovedBy:(ZBPackage *)package {
    for (ZBPackage *removedPackage in [[self removeQueue] copy]) {
        if ([[removedPackage removedBy] isEqual:package]) {
            [self removePackage:removedPackage inQueue:ZBQueueTypeRemove];
            [self removePackagesRemovedBy:removedPackage];
        }
    }
}

- (void)clear {
    for (NSMutableArray *array in [self queues]) {
        [array removeAllObjects];
    }
    [[self dependencyQueue] removeAllObjects];
    [[self conflictQueue] removeAllObjects];
    [queuedPackagesList removeAllObjects];
    [self updateQueueBarData];
    [self dismissQueueBar];
}

- (void)dismissQueueBar {
    [[ZBAppDelegate tabBarController] closeQueue];
}

- (NSArray *)tasksToPerform:(NSArray <NSDictionary <NSString*, NSString *> *> *)debs {
    NSMutableArray<NSArray *> *commands = [NSMutableArray new];
    NSArray *baseCommand;
    BOOL ignoreDependencies = [self containsPackageWithIgnoredDependencies]; //fallback to dpkg
    
    if (ignoreDependencies || [[ZBDevice packageManagementBinary] isEqualToString:@"/usr/bin/dpkg"]) {
        baseCommand = @[@"dpkg"];
    }
    else if ([[ZBDevice packageManagementBinary] isEqualToString:@"/usr/bin/apt"]) {
        baseCommand = @[@"apt", @"-yqf", @"--allow-downgrades", @"-oApt::Get::HideAutoRemove=true", @"-oquiet::NoProgress=true", @"-oquiet::NoStatistic=true"];
    }
    else {
        baseCommand = @[@"apt", @"-yqf", @"--allow-downgrades", @"-oApt::Get::HideAutoRemove=true", @"-oquiet::NoProgress=true", @"-oquiet::NoStatistic=true"];
    }
    
    NSString *binary = baseCommand[0];

    if ([self queueHasPackages:ZBQueueTypeRemove]) {
        if ([self containsEssentialOrRequiredPackage]) { //We need to use dpkg to remove these packages, I haven't found a flag that will enable APT to do this
            NSMutableArray *removeCommand = [@[@"dpkg", @"-r", @"--force-remove-essential"] mutableCopy];
            
            if (ignoreDependencies) {
                [removeCommand addObject:@"--force-depends"];
            }
            
            for (ZBPackage *package in [self removeQueue]) {
                if ([[package identifier] isEqualToString:@"xyz.willy.zebra"]) {
                    removingZebra = true;
                    continue;
                }
                [removeCommand addObject:package.identifier];
            }
            
            for (ZBPackage *package in [self conflictQueue]) {
                if ([[package identifier] isEqualToString:@"xyz.willy.zebra"]) {
                    removingZebra = true;
                    continue;
                }
                [removeCommand addObject:package.identifier];
            }
            
            [commands addObject:@[@(ZBStageRemove)]];
            [commands addObject:removeCommand];
        }
        else {
            NSMutableArray *removeCommand = [baseCommand mutableCopy];
            if ([binary isEqualToString:@"apt"]) {
                [removeCommand addObject:@"remove"];
            }
            else {
                [removeCommand addObject:@"-r"];
                if (ignoreDependencies) {
                    [removeCommand addObject:@"--force-depends"];
                }
            }
            
            for (ZBPackage *package in [self removeQueue]) {
                if ([[package identifier] isEqualToString:@"xyz.willy.zebra"]) {
                    removingZebra = true;
                    continue;
                }
                [removeCommand addObject:package.identifier];
            }
            
            for (ZBPackage *package in [self conflictQueue]) {
                if ([[package identifier] isEqualToString:@"xyz.willy.zebra"]) {
                    removingZebra = true;
                    continue;
                }
                [removeCommand addObject:package.identifier];
            }
            
            [commands addObject:@[@(ZBStageRemove)]];
            [commands addObject:removeCommand];
        }
    }
    
    BOOL installPackages   = [self queueHasPackages:ZBQueueTypeInstall];
    BOOL upgradePackages   = [self queueHasPackages:ZBQueueTypeUpgrade];
    BOOL downgradePackages = [self queueHasPackages:ZBQueueTypeDowngrade];
    if (installPackages || upgradePackages || downgradePackages) {
        NSMutableArray *installCommand = [baseCommand mutableCopy];
        if ([binary isEqualToString:@"apt"]) {
            [installCommand addObject:@"install"];
        }
        else {
            [installCommand addObject:@"-i"];
            if (ignoreDependencies) {
                [installCommand addObject:@"--force-depends"];
            }
        }
        
        NSArray *dependencyPaths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeDependency filenames:debs];
        [installCommand addObjectsFromArray:dependencyPaths];
        
        if (installPackages) {
            NSArray *paths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeInstall filenames:debs];
            [installCommand addObjectsFromArray:paths];
        }
        
        if (upgradePackages) {
            NSArray *paths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeUpgrade filenames:debs];
            [installCommand addObjectsFromArray:paths];
        }
        
        if (downgradePackages) {
            NSArray *paths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeDowngrade filenames:debs];
            [installCommand addObjectsFromArray:paths];
        }
        
        [commands addObject:@[@(ZBStageInstall)]];
        [commands addObject:installCommand];
    }
    
    if ([self queueHasPackages:ZBQueueTypeReinstall]) {
        [commands addObject:@[@(ZBStageReinstall)]];
        if ([binary isEqualToString:@"apt"]) {
            NSMutableArray *reinstallCommand = [baseCommand mutableCopy];
            [reinstallCommand addObject:@"install"];
            [reinstallCommand addObject:@"--reinstall"];
            
            NSArray *paths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeReinstall filenames:debs];
            [reinstallCommand addObjectsFromArray:paths];
            [commands addObject:reinstallCommand];
        }
        else if ([binary isEqualToString:@"dpkg"]) {
            //Remove package first
            NSMutableArray *removeCommand = [baseCommand mutableCopy];
            
            [removeCommand insertObject:@"-r" atIndex:1];
            [removeCommand insertObject:@"--force-depends" atIndex:2];
            for (ZBPackage *package in [self reinstallQueue]) {
                [removeCommand addObject:package.identifier];
            }
            [commands addObject:removeCommand];
            
            //Install new version
            NSMutableArray *installCommand = [baseCommand mutableCopy];
            [installCommand insertObject:@"-i" atIndex:1];
            NSArray *paths = [self pathsForDownloadedDebsInQueue:ZBQueueTypeReinstall filenames:debs];
            [installCommand addObjectsFromArray:paths];
            [commands addObject:installCommand];
        }
    }
    
    return commands;
}

- (NSArray <NSString *> *)pathsForDownloadedDebsInQueue:(ZBQueueType)queue filenames:(NSArray <NSDictionary <NSString*, NSString *> *> *)filenames {
    NSMutableArray *paths = [NSMutableArray new];
    for (ZBPackage *package in [self queueFromType:queue]) {
        BOOL isZebra = [[package identifier] isEqualToString:@"xyz.willy.zebra"];
        for (NSDictionary *filename in filenames) {
            NSString *finalPath = [filename objectForKey:@"final"];
            NSString *originalFilename = [filename objectForKey:@"original"];
            NSString *packageFilename = [[package filename] lastPathComponent];
            NSString *originalURL = [filename objectForKey:@"originalURL"];

            if (packageFilename == nil || originalFilename == nil || finalPath == nil) {
                continue;
            }
            
            if ([finalPath containsString:packageFilename]) {
                if (isZebra)
                    zebraPath = finalPath;
                else
                    [paths addObject:finalPath];
                break;
            }
            else if ([originalFilename containsString:packageFilename]) {
                if (isZebra)
                    zebraPath = finalPath;
                else
                    [paths addObject:finalPath];
                break;
            }
            else if ([originalURL containsString:packageFilename]) {
                if (isZebra)
                    zebraPath = finalPath;
                else
                    [paths addObject:finalPath];
                break;
            }
        }
    }
    
    return paths;
}

- (NSMutableArray *)queueFromType:(ZBQueueType)queue {
    return managedQueue[@(queue)];
}

- (BOOL)queueHasPackages:(ZBQueueType)queue {
    if (queue == ZBQueueTypeRemove) {
        return [managedQueue[@(queue)] count] || [[self conflictQueue] count];
    }
    else if (queue == ZBQueueTypeInstall) {
        return [managedQueue[@(queue)] count] || [[self dependencyQueue] count];
    }
    else {
        return [managedQueue[@(queue)] count];
    }
}

- (NSString *)displayableNameForQueueType:(ZBQueueType)queue useIcon:(BOOL)icon {
    BOOL useIcon = icon && [ZBDevice useIcon];
    
    switch (queue) {
        case ZBQueueTypeInstall:
            return useIcon ? @"↓" : NSLocalizedString(@"Install", @"");
        case ZBQueueTypeReinstall:
            return useIcon ? @"↺" : NSLocalizedString(@"Reinstall", @"");
        case ZBQueueTypeRemove:
            return useIcon ? @"╳" : NSLocalizedString(@"Remove", @"");
        case ZBQueueTypeUpgrade:
            return useIcon ? @"↑" : NSLocalizedString(@"Upgrade", @"");
        case ZBQueueTypeDowngrade:
            return useIcon ? @"⇵" : NSLocalizedString(@"Downgrade", @"");
        case ZBQueueTypeDependency:
            return useIcon ? @"↓" : NSLocalizedString(@"Install", @"");
        case ZBQueueTypeConflict:
            return useIcon ? @"╳" : NSLocalizedString(@"Remove", @"");
        default:
            break;
    }
    return @"This shouldn't be here...";
}

- (NSArray <NSNumber *> *)actionsToPerform {
    NSMutableArray *actions = [NSMutableArray new];
    
    for (ZBQueueType q = ZBQueueTypeInstall; q <= ZBQueueTypeDowngrade; q <<= 1) {
        if (
           managedQueue[@(q)].count
           || (q == ZBQueueTypeInstall && [self dependencyQueue].count)
           || (q == ZBQueueTypeRemove && [self conflictQueue].count)
        ) {
            [actions addObject:@(q)];
        }
    }

    return actions;
}

- (int)numberOfPackagesInQueue:(ZBQueueType)queue {
    return (int)[managedQueue[@(queue)] count];
}

- (BOOL)needsToDownloadPackages {
    for (NSNumber *key in managedQueue) {
        if (key.intValue != ZBQueueTypeRemove && [managedQueue[key] count]) {
            return YES;
        }
    }
    
    return NO;
}

- (NSArray *)packagesToDownload {
    NSMutableArray *packages = [NSMutableArray new];
    
    for (ZBQueueType q = ZBQueueTypeInstall; q <= ZBQueueTypeDowngrade; q <<= 1) {
        if (q != ZBQueueTypeRemove) {
            [packages addObjectsFromArray:[self queueFromType:q]];
        }
    }
    
    [packages addObjectsFromArray:[self dependencyQueue]];
    
    return (NSArray *)packages;
}

- (BOOL)contains:(ZBPackage *)package {
    if ([queuedPackagesList containsObject:[package identifier]]) {
        return YES;
    }
    
    for (NSNumber *key in managedQueue) {
        if ([managedQueue[key] containsObject:package]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)contains:(ZBPackage *)package inQueue:(ZBQueueType)queue {
    if (queue == ZBQueueTypeClear || queue == 0) {
        return [self contains:package];
    }
    else {
        NSMutableArray *queueArray = [self queueFromType:queue];
        if (!queueArray) return NO;
        for (ZBPackage *p in queueArray) {
            if ([p isEqual:package]) {
                return YES;
            }
        }
    }
    return NO;
}

- (NSArray <NSString *> *)queuedPackagesList {
    return queuedPackagesList;
}

- (NSArray <NSArray <ZBPackage *> *> *)topDownQueue {
    NSMutableArray *result = [NSMutableArray new];
    for (NSArray *queueArray in [self queues]) {
        NSMutableArray *topDownQueue = [queueArray mutableCopy];

        if (queueArray == [self installQueue]) {
            [topDownQueue addObjectsFromArray:[self dependencyQueue]];
        } else if (queueArray == [self removeQueue]) {
            [topDownQueue addObjectsFromArray:[self conflictQueue]];
        }

        if (topDownQueue.count) {
            [result addObject:topDownQueue];
        }
    }
    return result;
}

- (void)allDependenciesForPackage:(ZBPackage *)package dependencies:(NSMutableArray *)array {
    if (![array containsObject:package]) {
        [array addObject:package];
        for (ZBPackage *dependency in [package dependencies]) {
            [self allDependenciesForPackage:dependency dependencies:array];
        }
    }
}

- (NSString *)downloadSizeForQueue:(ZBQueueType)queueType {
    double totalDownloadSize = 0;
    NSMutableArray *packages = [[self queueFromType:queueType] mutableCopy];
    if (queueType == ZBQueueTypeInstall) {
        [packages addObjectsFromArray:[self dependencyQueue]];
    }
    
    for (ZBPackage *package in packages) {
        totalDownloadSize += [package downloadSize];
    }
    if (totalDownloadSize) {
        NSString *unit = @"bytes";
        if (totalDownloadSize > 1024 * 1024) {
            totalDownloadSize /= 1024 * 1024;
            unit = @"MB";
        }
        else if (totalDownloadSize > 1024) {
            totalDownloadSize /= 1024;
            unit = @"KB";
        }
        return [NSString stringWithFormat:@"%.2f %@", totalDownloadSize, unit];
    }
    
    return NULL;
}

- (ZBQueueType)locate:(ZBPackage *)package {
    for (NSNumber *key in managedQueue) {
        for (ZBPackage *queuedPackage in managedQueue[key]) {
            if ([[package identifier] isEqualToString:[queuedPackage identifier]]) {
                return key.intValue;
            }
        }
    }
    
    return ZBQueueTypeClear;
}

- (NSArray *)packageIDsQueuedForRemoval {
    NSMutableArray *result = [NSMutableArray new];
    for (ZBPackage *package in [self removeQueue]) {
        [result addObject:[package identifier]];
    }
    
    for (ZBPackage *package in [self conflictQueue]) {
        [result addObject:[package identifier]];
    }
    return result;
}

- (BOOL)hasIssues {
    return [[self issues] count];
}

- (NSArray <NSArray <NSString *> *> *)issues {
    NSMutableArray *issues = [NSMutableArray new];
    NSArray *topDownQueue = [self topDownQueue];
    for (NSArray *queueArray in topDownQueue) {
        for (ZBPackage *package in queueArray) {
            if ([package hasIssues]) {
                [issues addObjectsFromArray:[package issues]];
            }
        }
    }
    return issues;
}

- (BOOL)containsEssentialOrRequiredPackage {
    NSMutableArray *removedPackages = [[self removeQueue] mutableCopy];
    [removedPackages addObjectsFromArray:[self conflictQueue]];
    for (ZBPackage *package in removedPackages) {
        if ([package isEssentialOrRequired]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)containsPackageWithIgnoredDependencies {
    NSArray *topDownQueue = [self topDownQueue];
    for (NSArray *queueArray in topDownQueue) {
        for (ZBPackage *package in queueArray) {
            if ([package ignoreDependencies]) {
                return YES;
            }
        }
    }
    return NO;
}

- (NSArray <NSMutableArray *> *)queues {
    // The order must match those in ZBQueueType.h
    return @[[self installQueue], [self removeQueue], [self reinstallQueue], [self upgradeQueue], [self downgradeQueue]];
}

- (NSMutableArray *)installQueue {
    return managedQueue[@(ZBQueueTypeInstall)];
}

- (NSMutableArray *)reinstallQueue {
    return managedQueue[@(ZBQueueTypeReinstall)];
}

- (NSMutableArray *)removeQueue {
    return managedQueue[@(ZBQueueTypeRemove)];
}

- (NSMutableArray *)upgradeQueue {
    return managedQueue[@(ZBQueueTypeUpgrade)];
}

- (NSMutableArray *)downgradeQueue {
    return managedQueue[@(ZBQueueTypeDowngrade)];
}

- (NSMutableArray *)dependencyQueue {
    return managedQueue[@(ZBQueueTypeDependency)];
}

- (NSMutableArray *)conflictQueue {
    return managedQueue[@(ZBQueueTypeConflict)];
}

@end
