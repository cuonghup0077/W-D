//
//  ZBPackageManager.m
//  Zebra
//
//  Created by Wilson Styres on 10/11/20.
//  Copyright © 2020 Wilson Styres. All rights reserved.
//

#import "ZBPackageManager.h"

#import <string.h>
#import <ZBDevice.h>
#import <Managers/ZBDatabaseManager.h>
#import <Model/ZBPackage.h>
#import <Model/ZBSource.h>
#import <Helpers/utils.h>
#import <Database/ZBDependencyResolver.h>

@interface ZBPackageManager () {
    ZBDatabaseManager *databaseManager;
    NSMutableSet *uuids;
    sqlite_int64 currentUpdateDate;
}
@end

@implementation ZBPackageManager

@synthesize installedPackagesList = _installedPackagesList;

+ (instancetype)sharedInstance {
    static ZBPackageManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ZBPackageManager new];
    });
    return instance;
}

- (id)init {
    self = [super init];
    
    if (self) {
        databaseManager = [ZBDatabaseManager sharedInstance];
    }
    
    return self;
}

- (NSArray <ZBBasePackage *> *)packagesFromSource:(ZBSource *)source {
    return [self packagesFromSource:source inSection:NULL];
}

- (NSArray <ZBBasePackage *> *)packagesFromSource:(ZBSource *_Nullable)source inSection:(NSString *_Nullable)section {
    if ([source.uuid isEqualToString:@"_var_lib_dpkg_status_"] && [self needsStatusUpdate]) {
        ZBSource *localSource = [ZBSource localSource];
            
        [self importPackagesFromSource:localSource];
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"lastUpdatedStatusDate"];
        
        NSMutableDictionary *list = [NSMutableDictionary new];
        NSArray *packages = [databaseManager packagesFromSource:source inSection:section];
        for (ZBBasePackage *package in packages) {
            list[package.identifier] = package.version;
        }
        _installedPackagesList = list;
        
        return packages;
    } else {
        [databaseManager packagesWithUpdates];
        return [databaseManager packagesFromSource:source inSection:section];
    }
}

- (NSArray <ZBPackage *> *)latestPackages:(NSUInteger)limit {
    NSArray *latestPackages = [databaseManager latestPackages:limit];
    
    return latestPackages;
}

- (BOOL)needsStatusUpdate {
    NSError *fileError = nil;
    NSString *statusPath = [ZBDevice needsSimulation] ? [[NSBundle mainBundle] pathForResource:@"Installed" ofType:@"pack"] : @"/var/lib/dpkg/status";
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:statusPath error:&fileError];
    NSDate *lastModifiedDate = fileError != nil ? [NSDate distantPast] : [attributes fileModificationDate];
    NSDate *lastImportedDate = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastUpdatedStatusDate"];
    
    return [databaseManager numberOfPackagesInSource:[ZBSource localSource]] == 0 || !lastImportedDate || [lastImportedDate compare:lastModifiedDate] == NSOrderedAscending; // The date we last looked at the status file is less than the last modified date
}

- (NSDictionary <NSString *,NSString *> *)installedPackagesList {
    if ([self needsStatusUpdate]) {
        [self packagesFromSource:[ZBSource localSource]]; // This also updates the installed packages list
    } else if (!_installedPackagesList) {
        _installedPackagesList = [databaseManager packageListFromSource:[ZBSource localSource]];
    }
    
    return _installedPackagesList;
}

- (BOOL)isPackageInstalled:(ZBPackage *)package {
    return [self isPackageInstalled:package checkVersion:NO];
}

- (BOOL)isPackageInstalled:(ZBPackage *)package checkVersion:(BOOL)checkVersion {
    if (checkVersion) {
        NSString *version = [self.installedPackagesList objectForKey:package.identifier];
        if (!version) return NO;
        
        return [ZBDependencyResolver doesVersion:version satisfyComparison:@"=" ofVersion:package.version];
    } else {
        return [self.installedPackagesList objectForKey:package.identifier];
    }
}

- (void)importPackagesFromSource:(ZBBaseSource *)source {
    if (!source.packagesFilePath) return;
    
    uuids = [[databaseManager uniqueIdentifiersForPackagesFromSource:source] mutableCopy];
    currentUpdateDate = (sqlite3_int64)[[NSDate date] timeIntervalSince1970];
    
    [databaseManager performTransaction:^{
        FILE *file = fopen(source.packagesFilePath.UTF8String, "r");
        char line[2048];
        char **package = dualArrayOfSize(ZBPackageColumnCount);
        
        while (fgets(line, 2048, file)) {
            if (line[0] == '\n' || line[0] == '\r') {
                const char *identifier = package[ZBPackageColumnIdentifier];
                if (identifier && strcmp(identifier, "") != 0) {
                    if (!source.remote && package[ZBPackageColumnStatus]) {
                        const char *status = package[ZBPackageColumnStatus];
                        if (strcasestr(status, "config-files") != NULL || strcasestr(status, "not-installed") != NULL || strcasestr(status, "deinstall") != NULL) {
                            continue;
                        }
                    }
                    
                    if (!package[ZBPackageColumnName]) strcpy(package[ZBPackageColumnName], package[ZBPackageColumnIdentifier]);
                    
                    NSString *uniqueIdentifier = [NSString stringWithFormat:@"%s-%s-%@", package[ZBPackageColumnIdentifier], package[ZBPackageColumnVersion], source.uuid];
                    if (![self->uuids containsObject:uniqueIdentifier]) {
                        strcpy(package[ZBPackageColumnSource], source.uuid.UTF8String);
                        strcpy(package[ZBPackageColumnUUID], uniqueIdentifier.UTF8String);
                        memcpy(package[ZBPackageColumnLastSeen], &self->currentUpdateDate, sizeof(sqlite_int64 *));
                        
                        [self->databaseManager insertPackage:package];
                        
                        freeDualArrayOfSize(package, ZBPackageColumnCount);
                        package = dualArrayOfSize(ZBPackageColumnCount);
                    } else {
                        [self->uuids removeObject:uniqueIdentifier];
                    }
                }
            } else {
                char *key = strtok((char *)line, ":");
                ZBPackageColumn column = [self columnFromString:key];
                if (key && column < ZBPackageColumnCount) {
                    char *value = strtok(NULL, "");
                    if (value && value[0] == ' ') value++;
                    if (value) strcpy(package[column], trimWhitespaceFromString(value));
                }
            }
        }
        if (package) {
            const char *identifier = package[ZBPackageColumnIdentifier];
            if (identifier && strcmp(identifier, "") != 0) {
                if (!source.remote && package[ZBPackageColumnStatus]) {
                    const char *status = package[ZBPackageColumnStatus];
                    if (strcasestr(status, "config-files") != NULL || strcasestr(status, "not-installed") != NULL || strcasestr(status, "deinstall") != NULL) {
                        freeDualArrayOfSize(package, ZBPackageColumnCount);
                        fclose(file);
                        return;
                    }
                }
                
                if (!package[ZBPackageColumnName]) strcpy(package[ZBPackageColumnName], package[ZBPackageColumnIdentifier]);
                
                NSString *uniqueIdentifier = [NSString stringWithFormat:@"%s-%s-%@", package[ZBPackageColumnIdentifier], package[ZBPackageColumnVersion], source.uuid];
                if (![self->uuids containsObject:uniqueIdentifier]) {
                    strcpy(package[ZBPackageColumnSource], source.uuid.UTF8String);
                    strcpy(package[ZBPackageColumnUUID], uniqueIdentifier.UTF8String);
                    memcpy(package[ZBPackageColumnLastSeen], &self->currentUpdateDate, sizeof(sqlite_int64 *));
                    
                    [self->databaseManager insertPackage:package];
                    
                    freeDualArrayOfSize(package, ZBPackageColumnCount);
                    package = dualArrayOfSize(ZBPackageColumnCount);
                } else {
                    [self->uuids removeObject:uniqueIdentifier];
                }
            }
        }
        
        freeDualArrayOfSize(package, ZBPackageColumnCount);
        fclose(file);
    }];
    
    [databaseManager deletePackagesWithUniqueIdentifiers:uuids];
    [uuids removeAllObjects];
}

- (ZBPackageColumn)columnFromString:(char *)string {
    if (strcmp(string, "Author") == 0) {
        return ZBPackageColumnAuthorName;
    } else if (strcmp(string, "Description") == 0) {
        return ZBPackageColumnDescription;
    } else if (strcmp(string, "Package") == 0) {
        return ZBPackageColumnIdentifier;
    } else if (strcmp(string, "Name") == 0) {
        return ZBPackageColumnName;
    } else if (strcmp(string, "Version") == 0) {
        return ZBPackageColumnVersion;
    } else if (strcmp(string, "Section") == 0) {
        return ZBPackageColumnSection;
    } else if (strcmp(string, "Conflicts") == 0) {
        return ZBPackageColumnConflicts;
    } else if (strcmp(string, "Depends") == 0) {
        return ZBPackageColumnDepends;
    } else if (strcmp(string, "Depiction") == 0) {
        return ZBPackageColumnDepictionURL;
    } else if (strcmp(string, "Size") == 0) {
        return ZBPackageColumnDownloadSize;
    } else if (strcmp(string, "Essential") == 0) {
        return ZBPackageColumnEssential;
    } else if (strcmp(string, "Filename") == 0) {
        return ZBPackageColumnFilename;
    } else if (strcmp(string, "Homepage") == 0) {
        return ZBPackageColumnHomepageURL;
    } else if (strcmp(string, "Icon") == 0) {
        return ZBPackageColumnIconURL;
    } else if (strcmp(string, "Installed-Size") == 0) {
        return ZBPackageColumnInstalledSize;
    } else if (strcmp(string, "Maintainer") == 0) {
        return ZBPackageColumnMaintainerName;
    } else if (strcmp(string, "Priority") == 0) {
        return ZBPackageColumnPriority;
    } else if (strcmp(string, "Provides") == 0) {
        return ZBPackageColumnProvides;
    } else if (strcmp(string, "Replaces") == 0) {
        return ZBPackageColumnReplaces;
    } else if (strcmp(string, "SHA256") == 0) {
        return ZBPackageColumnSHA256;
    } else if (strcmp(string, "Status") == 0) {
        return ZBPackageColumnStatus;
    } else if (strcmp(string, "Tag") == 0) {
        return ZBPackageColumnTag;
    } else {
        return ZBPackageColumnCount;
    }
}

- (ZBPackage *_Nullable)installedInstanceOfPackage:(ZBPackage *)package {
    return [databaseManager installedInstanceOfPackage:package];
}

- (ZBPackage *_Nullable)packageWithUniqueIdentifier:(NSString *)uuid {
    return [databaseManager packageWithUniqueIdentifier:uuid];
}

- (NSArray <ZBPackage *> *)packagesByAuthorWithName:(NSString *)name email:(NSString *_Nullable)email {
    return [databaseManager packagesByAuthorWithName:name email:email];
}

- (BOOL)canReinstallPackage:(ZBPackage *)package {
    return [databaseManager isPackageAvailable:package checkVersion:YES];
}

// These search methods could be improved further by using a NSBlockOperation subclass to allow us to use sqlite3_interrupt but I'll come back to this idea later...
- (void)searchForPackagesByName:(NSString *)name completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    [databaseManager searchForPackagesByName:name completion:completion];
}

- (void)searchForPackagesByDescription:(NSString *)description completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    [databaseManager searchForPackagesByDescription:description completion:completion];
}

- (void)searchForPackagesByAuthorWithName:(NSString *)name completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    [databaseManager searchForPackagesByAuthorWithName:name completion:completion];
}

- (NSString *)installedVersionOfPackage:(ZBPackage *)package {
    return [databaseManager installedVersionOfPackage:package];
}

- (NSArray <ZBPackage *> *)allInstancesOfPackage:(ZBPackage *)package {
//    return [databaseManager allInstancesOfPackage:package];
    return NULL;
}

@end
