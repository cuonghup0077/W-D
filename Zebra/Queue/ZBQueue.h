//
//  ZBQueue.h
//  Zebra
//
//  Created by Wilson Styres on 1/29/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

@class UIColor;
@class ZBPackage;

@import Foundation;
#import <Queue/ZBQueueType.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZBQueue : NSObject
@property BOOL removingZebra;
@property (nonatomic, strong) NSString *zebraPath;
@property (nonatomic, strong) NSMutableArray<NSString *> *queuedPackagesList;
+ (id)sharedQueue;
+ (int)count;
+ (UIColor * _Nullable)colorForQueueType:(ZBQueueType)queue;
- (void)addPackage:(ZBPackage *)package toQueue:(ZBQueueType)queue;
- (void)addPackages:(NSArray <ZBPackage *> *)packages toQueue:(ZBQueueType)queue;
- (BOOL)addDependency:(ZBPackage *)package;
- (void)addConflict:(ZBPackage *)package;
- (void)removePackage:(ZBPackage *)package;
- (NSArray *)tasksToPerform;
- (NSMutableArray *)queueFromType:(ZBQueueType)queue;
- (NSArray <NSNumber *> *)actionsToPerform;
- (NSString * _Nullable)displayableNameForQueueType:(ZBQueueType)queue;
- (int)numberOfPackagesInQueue:(ZBQueueType)queue;
- (BOOL)needsToDownloadPackages;
- (NSArray *)packagesToDownload;
- (NSArray *)packagesToInstall;
- (BOOL)contains:(ZBPackage *)package inQueue:(ZBQueueType)queue;
- (NSArray <NSArray <ZBPackage *> *> *)topDownQueue;
- (NSString * _Nullable)downloadSizeForQueue:(ZBQueueType)queueType;
- (BOOL)hasIssues;
- (NSArray <NSArray <NSString *> *> *)issues;
- (void)clear;
- (NSMutableArray *)dependencyQueue;
- (NSMutableArray *)conflictQueue;
- (NSMutableArray <NSString *> *)queuedPackagesList;
- (ZBQueueType)locate:(ZBPackage *)package;
- (ZBQueueType)locatePackageID:(NSString *)packageID;
- (BOOL)containsEssentialOrRequiredPackage;
- (void)addConflict:(ZBPackage *)package removeDependencies:(BOOL)remove;

- (NSDictionary <NSString *, NSString *> *)packagesQueuedForAddition;
- (NSDictionary <NSString *, NSString *> *)installedPackagesListExcluding:(ZBPackage *_Nullable)exclude;
- (NSDictionary <NSString *, NSString *> *)virtualPackagesListExcluding:(ZBPackage *_Nullable)exclude;
- (NSArray <NSString *> *)packageIDsQueuedForRemoval;
@end

NS_ASSUME_NONNULL_END
