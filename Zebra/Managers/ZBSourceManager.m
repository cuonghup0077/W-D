//
//  ZBSourceManager.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#import "ZBSourceManager.h"

#import <Helpers/utils.h>
#import <Model/ZBSource.h>
#import <Model/ZBSourceFilter.h>
#import <Managers/ZBDatabaseManager.h>
#import <Managers/ZBPackageManager.h>
#import <Downloads/ZBDownloadManager.h>
#import <ZBAppDelegate.h>
#import <ZBDevice.h>
#import <ZBLog.h>
#import <ZBSettings.h>
#import <Tabs/Sources/Helpers/ZBSourceVerificationDelegate.h>

@import UIKit.UIDevice;

@interface ZBSourceManager () {
    NSMutableDictionary <NSString *, NSNumber *> *busyList;
    NSDictionary *pinPreferences;
    NSDictionary *sourceMap;
    
    ZBPackageManager *packageManager;
    ZBDatabaseManager *databaseManager;
    ZBDownloadManager *downloadManager;
}
@end

@implementation ZBSourceManager

@synthesize refreshInProgress;

NSString *const ZBStartedSourceRefreshNotification = @"StartedSourceRefresh";
NSString *const ZBStartedSourceDownloadNotification = @"StartedSourceDownload";
NSString *const ZBFinishedSourceDownloadNotification = @"FinishedSourceDownload";
NSString *const ZBStartedSourceImportNotification = @"StartedSourceImport";
NSString *const ZBFinishedSourceImportNotification = @"FinishedSourceImport";
NSString *const ZBUpdatesAvailableNotification = @"UpdatesAvailable";
NSString *const ZBFinishedSourceRefreshNotification = @"FinishedSourceRefresh";
NSString *const ZBAddedSourcesNotification = @"AddedSources";
NSString *const ZBRemovedSourcesNotification = @"RemovedSources";
NSString *const ZBSourceDownloadProgressUpdateNotification = @"SourceDownloadProgressUpdate";

#pragma mark - Initializers

+ (id)sharedInstance {
    static ZBSourceManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ZBSourceManager new];
    });
    return instance;
}

- (id)init {
    self = [super init];
    
    if (self) {
        databaseManager = [ZBDatabaseManager sharedInstance];
        packageManager = [ZBPackageManager sharedInstance];
        
        refreshInProgress = NO;
        
        pinPreferences = [self parsePreferences];
    }
    
    return self;
}

#pragma mark - Accessing Sources

- (NSArray <ZBSource *> *)sources {
    NSError *readError = NULL;
    NSSet *baseSources = [ZBBaseSource baseSourcesFromList:[ZBAppDelegate sourcesListURL] error:&readError];
    if (readError) {
        ZBLog(@"[Zebra] Error when reading sources from %@: %@", [ZBAppDelegate sourcesListURL], readError.localizedDescription);
        
        return [NSArray new];
    }
    
    if (!sourceMap) {
        NSSet *sourcesFromDatabase = [[ZBDatabaseManager sharedInstance] sources];
        NSSet *unionSet = [sourcesFromDatabase setByAddingObjectsFromSet:baseSources];
        
        NSMutableDictionary *tempSourceMap = [NSMutableDictionary new];
        for (ZBBaseSource *source in unionSet) {
            tempSourceMap[source.uuid] = source;
        }
        sourceMap = tempSourceMap;
    } else if (sourceMap && baseSources.count != sourceMap.allValues.count) { // A source was added to sources.list at some point by someone and we don't list it
//        NSMutableSet *cache = [NSMutableSet setWithArray:[sourceMap allValues]];
//
//        NSMutableSet *sourcesAdded = [baseSources mutableCopy];
//        [sourcesAdded minusSet:cache];
//        NSLog(@"[Zebra] Sources Added: %@", sourcesAdded);
//
//        NSMutableSet *sourcesRemoved = [cache mutableCopy];
//        [sourcesRemoved minusSet:baseSources];
//        NSLog(@"[Zebra] Sources Removed: %@", sourcesAdded);
//
//        if (sourcesAdded.count) [cache unionSet:sourcesAdded];
//        if (sourcesRemoved.count) [cache minusSet:sourcesRemoved];
//
//        NSMutableDictionary *tempSourceMap = [NSMutableDictionary new];
//        for (ZBBaseSource *source in cache) {
//            tempSourceMap[source.uuid] = source;
//        }
//        sourceMap = tempSourceMap;
//
//        if (sourcesAdded.count) [self bulkAddedSources:sourcesAdded];
//        if (sourcesRemoved.count) [self bulkRemovedSources:sourcesRemoved];
//
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
//            for (ZBSource *source in sourcesRemoved) {
//                [[ZBDatabaseManager sharedInstance] deleteSource:source];
//            }
//        });
    }
    
    return [sourceMap allValues];
}

- (ZBSource *)sourceWithUUID:(NSString *)UUID {
    return sourceMap[UUID];
}

#pragma mark - Adding and Removing Sources

- (void)addSources:(NSSet <ZBBaseSource *> *)sources error:(NSError **_Nullable)error {
    NSMutableSet *sourcesToAdd = [sources mutableCopy];
    for (ZBSource *source in sources) {
        if (sourceMap[source.uuid]) {
            ZBLog(@"[Zebra] %@ is already a source", source.repositoryURI); // This isn't going to trigger a failure, should it?
            [sourcesToAdd removeObject:source];
        }
    }
    
    if ([sourcesToAdd count]) {
        NSError *writeError = NULL;
        [self appendBaseSources:sourcesToAdd toFile:[ZBAppDelegate sourcesListPath] error:&writeError];
        
        if (writeError) {
            NSLog(@"[Zebra] Error while writing sources to file: %@", writeError);
            *error = writeError;
            return;
        }
        
        NSMutableDictionary *tempSourceMap = [sourceMap mutableCopy];
        for (ZBBaseSource *source in sourcesToAdd) {
            tempSourceMap[source.uuid] = source;
        }
        sourceMap = tempSourceMap;
        
        [self addedSources:sourcesToAdd];
        [self refreshSources:[sourcesToAdd allObjects] useCaching:NO error:nil];
    }
}

- (void)updateURIForSource:(ZBSource *)source oldURI:(NSString *)oldURI error:(NSError**_Nullable)error {
//    if (source != nil) {
//        NSSet *sourcesToWrite = [ZBBaseSource baseSourcesFromList:[ZBAppDelegate sourcesListURL] error:nil];
//
//        for (ZBBaseSource *baseSource in sourcesToWrite) {
//            if ([oldURI isEqualToString:baseSource.repositoryURI]) {
//                baseSource.repositoryURI = [source.repositoryURI copy];
//                break;
//            }
//        }
//
//        NSError *writeError = NULL;
//        [self writeBaseSources:sourcesToWrite toFile:[ZBAppDelegate sourcesListPath] error:&writeError];
//        if (writeError) {
//            NSLog(@"[Zebra] Error while writing sources to file: %@", writeError);
//            *error = writeError;
//            return;
//        }
//
//        [[ZBDatabaseManager sharedInstance] updateURIForSource:source];
//    }
}

- (void)removeSources:(NSSet <ZBBaseSource *> *)sources error:(NSError**_Nullable)error {
    NSMutableSet *sourcesToRemove = [sources mutableCopy];
    for (ZBSource *source in sources) {
        if (![source canDelete]) {
            ZBLog(@"[Zebra] %@ cannot be removed", source.repositoryURI); // This isn't going to trigger a failure, should it?
            [sourcesToRemove removeObject:source];
        }
    }
    
    if ([sourcesToRemove count]) {
        NSMutableSet *sourcesToWrite = [[ZBBaseSource baseSourcesFromList:[ZBAppDelegate sourcesListURL] error:nil] mutableCopy];
        [sourcesToWrite minusSet:sourcesToRemove];
        
        NSError *writeError = NULL;
        [self writeBaseSources:sourcesToWrite toFile:[ZBAppDelegate sourcesListPath] error:&writeError];
        if (writeError) {
            NSLog(@"[Zebra] Error while writing sources to file: %@", writeError);
            *error = writeError;
            return;
        }
        
        for (ZBSource *source in sourcesToRemove) {
            if ([source isKindOfClass:[ZBSource class]]) {
                // These actions should theoretically only be performed if the source is in the database as a base sources wouldn't be downloaded
                // Delete cached release/packages files (if they exist)
                NSArray *lists = [source lists];
                for (NSString *list in lists) {
                    NSString *path = [[ZBAppDelegate listsLocation] stringByAppendingPathComponent:list];
                    NSError *error = NULL;
                    if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
                        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
                        if (!success) {
                            NSLog(@"Error removing file at path: %@", error.localizedDescription);
                        }
                    }
                }
                
                // Delete files from featured.plist (if they exist)
                NSMutableDictionary *featured = [NSMutableDictionary dictionaryWithContentsOfFile:[[ZBAppDelegate documentsDirectory] stringByAppendingPathComponent:@"featured.plist"]];
                if ([featured objectForKey:[source uuid]]) {
                    [featured removeObjectForKey:[source uuid]];
                }
                [featured writeToFile:[[ZBAppDelegate documentsDirectory] stringByAppendingPathComponent:@"featured.plist"] atomically:NO];
                
                // Delete source and respective packages from database
                [[ZBDatabaseManager sharedInstance] deleteSource:source];
            }
        }
        
        NSMutableDictionary *tempSourceMap = [sourceMap mutableCopy];
        for (ZBBaseSource *source in sourcesToRemove) {
            [tempSourceMap removeObjectForKey:source.uuid];
        }
        sourceMap = tempSourceMap;
        
        [self removedSources:sourcesToRemove];
        [self finishedSourceRefresh];
    }
}

- (void)refreshSourcesUsingCaching:(BOOL)useCaching userRequested:(BOOL)requested error:(NSError **_Nullable)error {
    if (refreshInProgress)
        return;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL needsRefresh = NO;
        if (!requested && [ZBSettings wantsAutoRefresh]) {
            NSDate *currentDate = [NSDate date];
            NSDate *lastUpdatedDate = [self lastUpdated];

            if (lastUpdatedDate != NULL) {
                NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
                NSDateComponents *components = [calendar components:NSCalendarUnitMinute fromDate:lastUpdatedDate toDate:currentDate options:0];

                needsRefresh = ([components minute] >= 30);
            } else {
                needsRefresh = YES;
            }
        }

        [self updatesAvailable:self->packageManager.updates.count];
        NSMutableArray *sourcesToRefresh = [NSMutableArray arrayWithObjects:[ZBSource localSource], nil];
        if (requested || needsRefresh) [sourcesToRefresh addObjectsFromArray:self.sources];
        [self refreshSources:sourcesToRefresh useCaching:useCaching error:nil];
    });
}

- (NSDate *)lastUpdated {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"lastUpdated"];
}

- (void)updateLastUpdated {
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"lastUpdated"];
}

- (void)clearBusyList {
    [busyList enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        BOOL busy = [obj boolValue];
        if (busy) {
            [self finishedImportForSource:[self sourceWithUUID:key]];
        }
    }];
    [busyList removeAllObjects];
}

- (void)refreshSources:(NSArray <ZBBaseSource *> *)sources useCaching:(BOOL)useCaching error:(NSError **_Nullable)error {
    if (refreshInProgress)
        return;
    
    if (!busyList) busyList = [NSMutableDictionary new];
    else [self clearBusyList];
    
    for (ZBBaseSource *source in sources) {
        busyList[source.uuid] = @YES;
    }
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL hidden = sources.count == 1 && sources[0].remote == NO;
        [self startedSourceRefresh:hidden];
        self->downloadManager = [[ZBDownloadManager alloc] initWithDownloadDelegate:self];
        [self->downloadManager downloadSources:sources useCaching:useCaching];
        [self updateLastUpdated];
    });
}

- (void)appendBaseSources:(NSSet <ZBBaseSource *> *)sources toFile:(NSString *)filePath error:(NSError **_Nullable)error {
    NSError *readError = NULL;
    NSString *contents = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&readError];
    
    if (readError) {
        NSLog(@"[Zebra] ERROR while loading from sources.list: %@", readError);
        *error = readError;
        return;
    }
    else {
        NSMutableArray *debLines = [NSMutableArray new];
        for (ZBBaseSource *baseSource in sources) {
            [debLines addObject:[baseSource debLine]];
        }
        contents = [contents stringByAppendingString:[debLines componentsJoinedByString:@""]];
        
        NSError *writeError = NULL;
        [contents writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        
        if (writeError) {
            NSLog(@"[Zebra] Error while writing sources to file: %@", writeError);
            *error = writeError;
        }
    }
}

- (void)writeBaseSources:(NSSet <ZBBaseSource *> *)sources toFile:(NSString *)filePath error:(NSError **_Nullable)error {
    NSMutableArray *debLines = [NSMutableArray new];
    for (ZBBaseSource *baseSource in sources) {
        [debLines addObject:[baseSource debLine]];
    }
    
    NSError *writeError = NULL;
    [[debLines componentsJoinedByString:@""] writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (writeError) {
        NSLog(@"[Zebra] Error while writing sources to file: %@", writeError);
        *error = writeError;
    }
}

#pragma mark - Verifying Sources

- (void)verifySources:(NSSet <ZBBaseSource *> *)sources delegate:(id <ZBSourceVerificationDelegate>)delegate {
    if ([delegate respondsToSelector:@selector(startedSourceVerification:)]) [delegate startedSourceVerification:sources.count > 1];
    
    NSUInteger sourcesToVerify = sources.count;
    NSMutableArray *existingSources = [NSMutableArray new];
    NSMutableArray *imaginarySources = [NSMutableArray new];
    
    for (ZBBaseSource *source in sources) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [source verify:^(ZBSourceVerificationStatus status) {
                if ([delegate respondsToSelector:@selector(source:status:)]) [delegate source:source status:status];
                
                if (status == ZBSourceExists) {
                    [existingSources addObject:source];
                }
                else if (status == ZBSourceImaginary) {
                    [imaginarySources addObject:source];
                }
                
                if ([delegate respondsToSelector:@selector(finishedSourceVerification:imaginarySources:)] && sourcesToVerify == existingSources.count + imaginarySources.count) {
                    [delegate finishedSourceVerification:existingSources imaginarySources:imaginarySources];
                }
            }];
        });
    }
}

#pragma mark - Warnings

- (NSArray <NSError *> *)warningsForSource:(ZBBaseSource *)source {
    NSMutableArray *warnings = [NSMutableArray new];
    if ([source.mainDirectoryURL.scheme isEqual:@"http"] && ![self checkForAncientRepo:source.mainDirectoryURL.host]) {
        NSError *insecureError = [NSError errorWithDomain:ZBSourceErrorDomain code:ZBSourceWarningInsecure userInfo:@{
            NSLocalizedDescriptionKey: NSLocalizedString(@"Insecure Source", @""),
            NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"This repository is being accessed using an insecure scheme (HTTP). Switch to HTTPS to silence this warning.", @""),
        }];
        [warnings addObject:insecureError];
    }
    
    if ([self checkForInvalidRepo:source.mainDirectoryURL]) {
        NSError *insecureError = [NSError errorWithDomain:ZBSourceErrorDomain code:ZBSourceWarningIncompatible userInfo:@{
            NSLocalizedDescriptionKey: NSLocalizedString(@"Incompatible Source", @""),
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"This repository has been marked as incompatible with your jailbreak (%@). Installing packages from incompatible sources could result in crashes, inability to manage packages, and loss of jailbreak.", @""), [ZBDevice jailbreakType]], 
        }];
        [warnings addObject:insecureError];
    }
    
    return warnings.count ? warnings : NULL;
}

- (BOOL)checkForAncientRepo:(NSString *)baseURL {
    return [baseURL isEqualToString:@"apt.thebigboss.org"] || [baseURL isEqualToString:@"apt.modmyi.com"] || [baseURL isEqualToString:@"cydia.zodttd.com"] || [baseURL isEqualToString:@"apt.saurik.com"];
}

- (BOOL)checkForInvalidRepo:(NSURL *)baseURL {
    NSString *host = [baseURL host];
    
    if ([ZBDevice isOdyssey]) { // odyssey
        return ([host isEqualToString:@"checkra.in"] || [host isEqualToString:@"apt.saurik.com"] || [host isEqualToString:@"electrarepo64.coolstar.org"] || [host isEqualToString:@"repo.chimera.sh"] || [host isEqualToString:@"apt.bingner.com"]);
    }
    if ([ZBDevice isCheckrain]) { // checkra1n
        return ([host isEqualToString:@"apt.saurik.com"] || [host isEqualToString:@"electrarepo64.coolstar.org"] || [host isEqualToString:@"repo.chimera.sh"] || [host isEqualToString:@"apt.procurs.us"]);
    }
    if ([ZBDevice isChimera]) { // chimera
        return ([host isEqualToString:@"checkra.in"] || [host isEqualToString:@"apt.bingner.com"] || [host isEqualToString:@"apt.saurik.com"] || [host isEqualToString:@"electrarepo64.coolstar.org"] || [host isEqualToString:@"apt.procurs.us"]);
    }
    if ([ZBDevice isUncover]) { // uncover
        return ([host isEqualToString:@"checkra.in"] || [host isEqualToString:@"repo.chimera.sh"] || [host isEqualToString:@"apt.saurik.com"] || [host isEqualToString:@"electrarepo64.coolstar.org"] || [host isEqualToString:@"apt.procurs.us"]);
    }
    if ([ZBDevice isElectra]) { // electra
        return ([host isEqualToString:@"checkra.in"] || [host isEqualToString:@"repo.chimera.sh"] || [host isEqualToString:@"apt.saurik.com"] || [host isEqualToString:@"apt.bingner.com"] || [host isEqualToString:@"apt.procurs.us"]);
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Cydia.app"]) { // cydia
        return ([host isEqualToString:@"checkra.in"] || [host isEqualToString:@"repo.chimera.sh"] || [host isEqualToString:@"electrarepo64.coolstar.org"] || [host isEqualToString:@"apt.bingner.com"] || [host isEqualToString:@"apt.procurs.us"]);
    }
    
    return NO;
}

#pragma mark - Download Delegate

- (void)startedDownloads {
    ZBLog(@"[Zebra](ZBSourceManager) Started downloads");
}

- (void)startedDownloadingSource:(ZBBaseSource *)source {
    ZBLog(@"[Zebra](ZBSourceManager) Started downloading %@", source);
    
    [self startedDownloadForSource:source];
}

- (void)progressUpdate:(CGFloat)progress forSource:(ZBBaseSource *)baseSource {
    ZBLog(@"[Zebra](ZBSourceManager) Progress update for %@", baseSource);
}

- (void)finishedDownloadingSource:(ZBBaseSource *)source withError:(NSArray <NSError *> *)errors {
    ZBLog(@"[Zebra](ZBSourceManager) Finished downloading %@", source);
    
    if (source) {
        if (errors && errors.count) {
            source.errors = errors;
            source.warnings = [self warningsForSource:source];
        }

        [self finishedDownloadForSource:source];
        [self importSource:source];
    }
}

- (void)finishedAllDownloads {
    ZBLog(@"[Zebra](ZBSourceManager) Finished all downloads");
    downloadManager = NULL;
}

#pragma mark - Importing Sources

- (void)importSource:(ZBBaseSource *)baseSource {
    [self startedImportForSource:baseSource];
    
    if (baseSource.remote && baseSource.releaseFilePath) {
        FILE *file = fopen(baseSource.releaseFilePath.UTF8String, "r");
        char line[2048];
        char **source = dualArrayOfSize(ZBSourceColumnCount);
        
        while (fgets(line, 2048, file)) {
            if (line[0] != '\n' && line[0] != '\r') {
                char *key = strtok((char *)line, ":");
                ZBSourceColumn column = [self columnFromString:key];
                if (key && column < ZBSourceColumnCount) {
                    char *value = strtok(NULL, ":");
                    if (value && value[0] == ' ') value++;
                    if (value) strcpy(source[column], trimWhitespaceFromString(value));
                }
            }
        }
        
        strcpy(source[ZBSourceColumnArchiveType], baseSource.archiveType.UTF8String);
        
        const char *components = [baseSource.components componentsJoinedByString:@" "].UTF8String;
        if (components) strcpy(source[ZBSourceColumnComponents], components);
        
        strcpy(source[ZBSourceColumnDistribution], baseSource.distribution.UTF8String);
        
        strcpy(source[ZBSourceColumnURL], baseSource.repositoryURI.UTF8String);
        strcpy(source[ZBSourceColumnUUID], baseSource.uuid.UTF8String);
        
        if ([baseSource.paymentEndpointURL.scheme isEqual:@"https"]) {
            NSString *paymentEndpointString = baseSource.paymentEndpointURL.absoluteString;
            if (paymentEndpointString) strcpy(source[ZBSourceColumnPaymentEndpoint], paymentEndpointString.UTF8String);
        } else {
            strcpy(source[ZBSourceColumnPaymentEndpoint], "\0");
        }
        
        int supportsFeatured = baseSource.supportsFeaturedPackages;
        memcpy(source[ZBSourceColumnSupportsFeaturedPackages], &supportsFeatured, 1);
        
        ZBSource *createdSource = [databaseManager insertSource:source];
        if (createdSource) {
            NSMutableDictionary *tempSourceMap = sourceMap.mutableCopy;
            tempSourceMap[baseSource.uuid] = createdSource;
            sourceMap = tempSourceMap;
        }
        
        freeDualArrayOfSize(source, ZBSourceColumnCount);
        fclose(file);
    }
    
    [packageManager importPackagesFromSource:baseSource];
    [self finishedImportForSource:sourceMap[baseSource.uuid] ?: baseSource];
}

- (ZBSourceColumn)columnFromString:(char *)string {
    if (strcmp(string, "Author") == 0) {
        return ZBSourceColumnArchitectures;
    }
    if (strcmp(string, "Codename") == 0) {
        return ZBSourceColumnCodename;
    }
    if (strcmp(string, "Label") == 0) {
        return ZBSourceColumnLabel;
    }
    if (strcmp(string, "Origin") == 0) {
        return ZBSourceColumnOrigin;
    }
    if (strcmp(string, "Description") == 0) {
        return ZBSourceColumnDescription;
    }
    if (strcmp(string, "Suite") == 0) {
        return ZBSourceColumnSuite;
    }
    if (strcmp(string, "Version") == 0) {
        return ZBSourceColumnVersion;
    }
    return ZBSourceColumnCount;
}

#pragma mark - Reading Pin Priorities

- (NSInteger)pinPriorityForSource:(ZBSource *)source {
    return [self pinPriorityForSource:source strict:NO];
}

- (NSInteger)pinPriorityForSource:(ZBSource *)source strict:(BOOL)strict {
    if (!source.remote) return 100;
    
    if ([pinPreferences objectForKey:source.origin]) {
        return [[pinPreferences objectForKey:source.origin] integerValue];
    }
    if ([pinPreferences objectForKey:source.label]) {
        return [[pinPreferences objectForKey:source.label] integerValue];
    }
    if ([pinPreferences objectForKey:source.codename]) {
        return [[pinPreferences objectForKey:source.codename] integerValue];
    }
    if (!strict) {
        return 500;
    }
    return 499;
}

- (NSDictionary *)parsePreferences {
    NSMutableDictionary *priorities = [NSMutableDictionary new];
    NSArray *preferences = [self prioritiesForFile:[ZBDevice needsSimulation] ? [[NSBundle mainBundle] pathForResource:@"pin" ofType:@"pref"] : @"/etc/apt/preferences.d/"];
    
    for (NSDictionary *preference in preferences) {
        NSInteger pinPriority = [preference[@"Pin-Priority"] integerValue];
        NSString *pin = preference[@"Pin"];
        if (pin == NULL) continue;
        
        NSRange rangeOfSpace = [pin rangeOfString:@" "];
        NSString *value = rangeOfSpace.location == NSNotFound ? pin : [pin substringToIndex:rangeOfSpace.location];
        NSString *options = rangeOfSpace.location == NSNotFound ? nil :[pin substringFromIndex:rangeOfSpace.location + 1];
        if (!value || !options) continue;
        
        if ([value isEqualToString:@"origin"]) {
            [priorities setValue:@(pinPriority) forKey:options];
        } else if ([value isEqualToString:@"release"]) {
            NSArray *components = [options componentsSeparatedByString:@", "];
            if (components.count == 1 && [options containsString:@","]) components = [options componentsSeparatedByString:@","];
            
            for (NSString *option in components) {
                NSArray *components = [option componentsSeparatedByString:@"="];
                NSArray *choices = @[@"o", @"l", @"n"];
                
                if (components.count == 2 && [choices containsObject:components[0]]) {
                    [priorities setValue:@(pinPriority) forKey:[components[1] stringByReplacingOccurrencesOfString:@"\"" withString:@""]];
                }
            }
        }
    }
    
    return priorities;
}

- (NSArray *)prioritiesForFile:(NSString *)path {
    BOOL isDirectory = NO;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (isDirectory) {
        NSMutableArray *prioritiesForDirectory = [NSMutableArray new];
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
        NSString *directory;
        NSString *file;
        
        if ([path hasSuffix:@"/"]) {
            directory = [path copy];
        } else {
            directory = [path stringByAppendingString:@"/"];
        }

        while (file = [enumerator nextObject]) {
            file = [directory stringByAppendingString:file];
            [prioritiesForDirectory addObjectsFromArray:[self prioritiesForFile:file]];
        }
        return prioritiesForDirectory;
    } else if (fileExists) {
        NSError *readError = NULL;
        NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readError];
        if (readError) return @[];
        
        NSMutableArray *prioritiesForFile = [NSMutableArray new];
        __block NSMutableDictionary *currentGroup = [NSMutableDictionary new];
        [contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            if ([line isEqual:@""]) {
                [prioritiesForFile addObject:currentGroup];
                currentGroup = [NSMutableDictionary new];
            }
            
            NSArray <NSString *> *pair = [line componentsSeparatedByString:@": "];
            if (pair.count != 2) pair = [line componentsSeparatedByString:@":"];
            if (pair.count != 2) return;
            NSString *key = [pair[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *value = [pair[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            
            [currentGroup setValue:value forKey:key];
        }];
        if (currentGroup.allValues.count) [prioritiesForFile addObject:currentGroup];
        
        return prioritiesForFile;
    }
    
    return @[];
}

#pragma mark - Source Delegate Notifiers

- (void)startedSourceRefresh:(BOOL)hidden {
    refreshInProgress = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBStartedSourceRefreshNotification object:self userInfo:@{@"hidden": @(hidden)}];
}

- (void)startedDownloadForSource:(ZBBaseSource *)source {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBStartedSourceDownloadNotification object:self userInfo:@{@"source": source}];
}

- (void)finishedDownloadForSource:(ZBBaseSource *)source {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBFinishedSourceDownloadNotification object:self userInfo:@{@"source": source}];
}

- (void)startedImportForSource:(ZBBaseSource *)source {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBStartedSourceImportNotification object:self userInfo:@{@"source": source}];
}

- (void)finishedImportForSource:(ZBBaseSource *)source {
    busyList[source.uuid] = @NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBFinishedSourceImportNotification object:self userInfo:@{@"source": source}];
    
    @synchronized (busyList) {
        __block BOOL finished = YES;
        [busyList enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            BOOL busy = [obj boolValue];
            if (busy) {
                finished = NO;
                *stop = YES;
            }
        }];
        if (finished) [self finishedSourceRefresh];
    }
}

- (void)finishedSourceRefresh {
    refreshInProgress = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBFinishedSourceRefreshNotification object:self];
    
    [self updatesAvailable:packageManager.updates.count];
}


- (void)addedSources:(NSSet <ZBBaseSource *> *)sources {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBAddedSourcesNotification object:self userInfo:@{@"sources": sources}];
}

- (void)removedSources:(NSSet <ZBBaseSource *> *)sources {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBRemovedSourcesNotification object:self userInfo:@{@"sources": sources}];
}

- (void)updatesAvailable:(NSUInteger)numberOfUpdates {
    [[NSNotificationCenter defaultCenter] postNotificationName:ZBUpdatesAvailableNotification object:self userInfo:@{@"updates": @(numberOfUpdates)}];
}

- (void)cancelSourceRefresh {
    [downloadManager stopAllDownloads];
    [self clearBusyList];
}

- (NSDictionary <NSString *, NSNumber *> *)sectionsForSource:(ZBSource *)source {
    return [databaseManager sectionReadoutForSource:source];
}

- (NSUInteger)numberOfPackagesInSource:(ZBSource *)source {
    return [databaseManager numberOfPackagesInSource:source];
}

- (NSArray<ZBSource *> *)filterSources:(NSArray<ZBSource *> *)sources withFilter:(ZBSourceFilter *)filter {
    if (!filter) return sources;
    
    NSArray *filteredPackages = [sources filteredArrayUsingPredicate:filter.compoundPredicate];
    return [filteredPackages sortedArrayUsingDescriptors:filter.sortDescriptors];
}

- (BOOL)isSourceBusy:(ZBBaseSource *)source {
    if (!source.uuid) return NO;
    
    return [busyList[source.uuid] boolValue];
}

@end
