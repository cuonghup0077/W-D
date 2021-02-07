//
//  ZBDatabaseManager.m
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

#define DATABASE_VERSION 2
#define PACKAGES_TABLE_NAME "packages"
#define SOURCES_TABLE_NAME "sources"
#define BASE_PACKAGE_COLUMNS "p.authorName, p.description, p.downloadSize, p.iconURL, p.identifier, p.installedSize, p.lastSeen, p.name, p.role, p.section, p.source, p.tag, p.uuid, p.version"

#import "ZBDatabaseManager.h"

@import SQLite3;
@import FirebaseAnalytics;

#import <ZBAppDelegate.h>
#import <ZBLog.h>
#import <Database/ZBDependencyResolver.h>
#import <Helpers/utils.h>
#import <Model/ZBSource.h>
#import <Model/ZBPackage.h>
#import <Queue/ZBQueue.h>
#import <Managers/ZBPackageManager.h>
#import <ZBSettings.h>
#import <Database/ZBDependencyResolver.h>

typedef NS_ENUM(NSUInteger, ZBDatabaseStatementType) {
    ZBDatabaseStatementTypePackagesFromSource,
    ZBDatabaseStatementTypePackageListFromSource,
    ZBDatabaseStatementTypeVirtualPackageListFromSource,
    ZBDatabaseStatementTypePackagesFromSourceAndSection,
    ZBDatabaseStatementTypeUUIDsFromSource,
    ZBDatabaseStatementTypePackagesWithUUID,
    ZBDatabaseStatementTypeAllVersionsOfPackages,
    ZBDatabaseStatementTypeAllInstancesOfPackage,
    ZBDatabaseStatementTypeHighestVersionOfPackage,
    ZBDatabaseStatementTypeBasePackageWithVersion,
    ZBDatabaseStatementTypeLatestPackages,
    ZBDatabaseStatementTypeLatestPackagesWithLimit,
    ZBDatabaseStatementTypeInstalledInstanceOfPackage,
    ZBDatabaseStatementTypeInstalledVersionOfPackage,
    ZBDatabaseStatementTypeRemoteInstanceOfPackageWithVersion,
    ZBDatabaseStatementTypeIsPackageAvailable,
    ZBDatabaseStatementTypeIsPackageAvailableWithVersion,
    ZBDatabaseStatementTypeSearchForPackageWithName,
    ZBDatabaseStatementTypeSearchForPackageWithDescription,
    ZBDatabaseStatementTypeSearchForPackageByAuthorName,
    ZBDatabaseStatementTypeSearchForPackageByAuthorNameAndEmail,
    ZBDatabaseStatementTypeRemovePackageWithUUID,
    ZBDatabaseStatementTypeInsertPackage,
    ZBDatabaseStatementTypeSources,
    ZBDatabaseStatementTypeSourceWithUUID,
    ZBDatabaseStatementTypeInsertSource,
    ZBDatabaseStatementTypeSearchAuthorsByName,
    ZBDatabaseStatementTypeSectionReadout,
    ZBDatabaseStatementTypeSectionsReadout,
    ZBDatabaseStatementTypePackagesInSourceCount,
    ZBDatabaseStatementTypeInstalledPackages,
    ZBDatabaseStatementTypeCount
};

@interface ZBDatabaseManager () {
    sqlite3 *database;
    NSString *databasePath;
    sqlite3_stmt **preparedStatements;
    dispatch_queue_t searchQueue;
    dispatch_block_t currentSearchBlock;
}
@end

@implementation ZBDatabaseManager

#pragma mark - Initializers

+ (instancetype)sharedInstance {
    static ZBDatabaseManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ZBDatabaseManager new];
    });
    return instance;
}

- (instancetype)init {
    return [self initWithPath:[ZBAppDelegate databaseLocation]];
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    
    if (self) {
        databasePath = path;
        
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_BACKGROUND, 0);
        searchQueue = dispatch_queue_create("xyz.willy.Zebra.search", attributes);
        
        if (![self connectToDatabase]) {
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc {
    if (database) {
        [self disconnectFromDatabase];
    }
}

#pragma mark - Opening and Closing the Database

- (BOOL)connectToDatabase {
    BOOL ret = YES;
    ZBLog(@"[Zebra] Initializing database at %@", databasePath);
    
    int result = [self openDatabase];
    if (result != SQLITE_OK) {
        ZBLog(@"[Zebra] Failed to open database at %@", databasePath);
    }
    
    if (![self needsMigration]) {
        if (result == SQLITE_OK) {
            result = sqlite3_create_function(database, "maxversion", 1, SQLITE_UTF8, NULL, NULL, maxVersionStep, maxVersionFinal);
            if (result != SQLITE_OK) {
                ZBLog(@"[Zebra] Failed to create aggregate function at %@", databasePath);
            }
        }
        
        if (result == SQLITE_OK) {
            result = [self initializePreparedStatements];
            if (result != SQLITE_OK) {
                ZBLog(@"[Zebra] Failed to initialize prepared statements at %@", databasePath);
            }
        }
        
        if (result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to initialize database at %@", databasePath);
            ret = NO;
        }
    } else {
        ZBLog(@"[Zebra] Database needs migration, not continuing.");
    }
    return ret;
}

- (void)disconnectFromDatabase {
    if (preparedStatements) {
        for (unsigned int i = 0; i < ZBDatabaseStatementTypeCount; i++) {
            sqlite3_stmt *statement = preparedStatements[i];
            if (statement) sqlite3_finalize(statement);
        }
        free(preparedStatements);
        preparedStatements = NULL;
    }
    [self closeDatabase];
}

- (int)openDatabase {
    int flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN | SQLITE_OPEN_FULLMUTEX;
    return sqlite3_open_v2(databasePath.UTF8String, &database, flags, NULL);
}

- (int)closeDatabase {
    int result = SQLITE_ERROR;
    if (database) {
        result = sqlite3_close(database);
        if (result == SQLITE_OK) {
            database = NULL;
        } else {
            NSLog(@"[Zebra] Failed to close database path: %@", databasePath);
        }
    } else {
        NSLog(@"[Zebra] Attempt to close null database handle");
    }
    return result;
}

#pragma mark - Database Migration

- (BOOL)needsMigration {
    return [self schemaVersion] < DATABASE_VERSION;
}

- (int)schemaVersion {
    sqlite3_stmt *statement;
    const char *query = "PRAGMA user_version;";
    
    int schemaVersion = 0;
    int result = sqlite3_prepare_v2(database, query, -1, &statement, nil);
    if (result == SQLITE_OK) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            schemaVersion = sqlite3_column_int(statement, 0);
        }
    }
    sqlite3_finalize(statement);
    ZBLog(@"[Zebra] Current Schema Version: %d", schemaVersion);
    return schemaVersion;
}

- (void)setSchemaVersion {
    ZBLog(@"[Zebra] Setting Schema Version to %d", DATABASE_VERSION);
    
    NSString *query = [NSString stringWithFormat:@"PRAGMA user_version = %d;", DATABASE_VERSION];
    sqlite3_exec(database, query.UTF8String, nil, nil, nil);
}

- (void)migrateDatabase:(BOOL)force {
    int version = [self schemaVersion];
    if (version >= DATABASE_VERSION && !force) return;
    
    ZBLog(@"[Zebra] Migrating database from version %d to %d", version, DATABASE_VERSION);
    
    [self performTransaction:^{
        switch (version + 1) {
            case 1: {
                // First major DB revision, we need to migration ignore update preferences and likely drop everything else due to the size of the changes.
                
                // Drop old PACKAGES and REPOS tables. We can easily recover the data with a source refresh.
                sqlite3_exec(self->database, "DROP TABLE PACKAGES;", nil, nil, nil);
                sqlite3_exec(self->database, "DROP TABLE REPOS;", nil, nil, nil);
                
                // Transfer updates from old UPDATES table to NSUserDefaults
                sqlite3_stmt *statement;
                const char *query = "SELECT PACKAGE FROM UPDATES WHERE IGNORE = 1;";
                int result = sqlite3_prepare_v2(self->database, query, -1, &statement, nil);
                if (result == SQLITE_OK) {
                    do {
                        result = sqlite3_step(statement);
                        if (result == SQLITE_ROW) {
                            const char *identifier = (const char *)sqlite3_column_text(statement, 0);
                            if (identifier) {
                                [ZBSettings setUpdatesIgnored:YES forPackageIdentifier:[NSString stringWithUTF8String:identifier]];
                            }
                        }
                    } while (result == SQLITE_ROW);
                }
                
                sqlite3_finalize(statement);
                
                // Drop old UPDATES table. Updates aren't store separately anymore.
                sqlite3_exec(self->database, "DROP TABLE UPDATES;", nil, nil, nil);
                
                // Create new tables
                [self initializePackagesTable];
                [self initializeSourcesTable];
                break;
            }
            default: {
                // Had some database corruption in DBv1, so we're forcing a migration to version latest in order to get rid of all corrupted packages
                
                // Drop old packages and sources tables. We can easily recover the data with a source refresh.
                sqlite3_exec(self->database, "DROP TABLE packages;", nil, nil, nil);
                sqlite3_exec(self->database, "DROP TABLE sources;", nil, nil, nil);
                
                // Create new tables
                [self initializePackagesTable];
                [self initializeSourcesTable];
            }
        }
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lastUpdated"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lastUpdatedStatusDate"];
        [self setSchemaVersion];
    }];
    
    [self disconnectFromDatabase];
    [self connectToDatabase];
}

#pragma mark - Creating Tables

- (int)initializePackagesTable {
    int result = SQLITE_ERROR;
    NSString *createTableStatement = @"CREATE TABLE IF NOT EXISTS " PACKAGES_TABLE_NAME
                                          "(authorName TEXT, "
                                          "description TEXT, "
                                          "downloadSize INTEGER, "
                                          "iconURL TEXT, "
                                          "identifier TEXT, "
                                          "installedSize INTEGER, "
                                          "lastSeen DATE, "
                                          "name TEXT, "
                                          "role INTEGER, "
                                          "section TEXT, "
                                          "source TEXT, "
                                          "tag TEXT, "
                                          "uuid TEXT, "
                                          "version TEXT, "
                                          "authorEmail TEXT, "
                                          "conflicts TEXT, "
                                          "depends TEXT, "
                                          "depictionURL TEXT, "
                                          "essential BOOLEAN, "
                                          "filename TEXT, "
                                          "header TEXT, "
                                          "homepageURL TEXT, "
                                          "maintainerEmail TEXT, "
                                          "maintainerName TEXT, "
                                          "priority TEXT, "
                                          "provides TEXT, "
                                          "replaces TEXT, "
                                          "sha256 TEXT, "
                                          "PRIMARY KEY(uuid)) "
                                          "WITHOUT ROWID;";
    result = sqlite3_exec(database, [createTableStatement UTF8String], NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        ZBLog(@"[Zebra] Failed to create packages table with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }

    if (result == SQLITE_OK) {
        NSString *createIndexStatement = @"CREATE INDEX IF NOT EXISTS uuid ON " PACKAGES_TABLE_NAME "(uuid);";
        result = sqlite3_exec(database, [createIndexStatement UTF8String], NULL, NULL, NULL);
        if (result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to create uuid index on packages table with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    return result;
}

- (int)initializeSourcesTable {
    int result = SQLITE_ERROR;
    NSString *createTableStatement = @"CREATE TABLE IF NOT EXISTS " SOURCES_TABLE_NAME
                                          "(architectures TEXT, "
                                          "archiveType TEXT, "
                                          "codename TEXT, "
                                          "components TEXT, "
                                          "distribution TEXT, "
                                          "label TEXT, "
                                          "origin TEXT, "
                                          "paymentEndpoint TEXT, "
                                          "sourceDescription TEXT, "
                                          "suite TEXT, "
                                          "supportsFeaturedPackages INTEGER, "
                                          "url TEXT, "
                                          "uuid TEXT, "
                                          "version TEXT, "
                                          "PRIMARY KEY(uuid)) "
                                          "WITHOUT ROWID;";
    result = sqlite3_exec(database, [createTableStatement UTF8String], NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        ZBLog(@"[Zebra] Failed to create sources table with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }

    if (result == SQLITE_OK) {
        NSString *createIndexStatement = @"CREATE INDEX IF NOT EXISTS uuid ON " SOURCES_TABLE_NAME "(uuid);";
        result = sqlite3_exec(database, [createIndexStatement UTF8String], NULL, NULL, NULL);
        if (result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to create uuid index on sources table with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    return result;
}

#pragma mark - Statement Preparation

- (NSString *)statementStringForStatementType:(ZBDatabaseStatementType)statement {
    switch (statement) {
        case ZBDatabaseStatementTypePackagesFromSource:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version, source FROM " PACKAGES_TABLE_NAME " WHERE source = ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version AND p.source = v.source;";
        case ZBDatabaseStatementTypePackageListFromSource:
            return @"SELECT p.identifier, p.version FROM (SELECT identifier, maxversion(version) AS max_version, source FROM " PACKAGES_TABLE_NAME " WHERE source = ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version AND p.source = v.source;";
        case ZBDatabaseStatementTypeVirtualPackageListFromSource:
            return @"SELECT p.provides FROM (SELECT identifier, maxversion(version) AS max_version, source FROM " PACKAGES_TABLE_NAME " WHERE source = ? AND provides != \'\' AND provides NOT NULL GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version AND p.source = v.source;";
        case ZBDatabaseStatementTypePackagesFromSourceAndSection:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version, source FROM " PACKAGES_TABLE_NAME " WHERE source = ? AND section = ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version AND p.source = v.source;";
        case ZBDatabaseStatementTypeUUIDsFromSource:
            return @"SELECT uuid FROM " PACKAGES_TABLE_NAME " WHERE source = ?";
        case ZBDatabaseStatementTypePackagesWithUUID:
            return @"SELECT * FROM " PACKAGES_TABLE_NAME " WHERE uuid = ?;";
        case ZBDatabaseStatementTypeAllVersionsOfPackages:
            return @"SELECT version FROM " PACKAGES_TABLE_NAME " WHERE identifier = ?;";
        case ZBDatabaseStatementTypeAllInstancesOfPackage:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM " PACKAGES_TABLE_NAME " AS p WHERE identifier = ?;";
        case ZBDatabaseStatementTypeHighestVersionOfPackage:
            return @"SELECT maxversion(version) FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? GROUP BY identifier;";
        case ZBDatabaseStatementTypeBasePackageWithVersion:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM " PACKAGES_TABLE_NAME " AS p WHERE identifier = ? AND version = ?;";
        case ZBDatabaseStatementTypeLatestPackages:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE source != \'_var_lib_dpkg_status_\' GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.lastSeen DESC, p.name;";
        case ZBDatabaseStatementTypeLatestPackagesWithLimit:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE source != \'_var_lib_dpkg_status_\' GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.lastSeen DESC, p.name LIMIT ?;";
        case ZBDatabaseStatementTypeInstalledInstanceOfPackage:
            return @"SELECT * FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? AND source = \'_var_lib_dpkg_status_\';";
        case ZBDatabaseStatementTypeInstalledVersionOfPackage:
            return @"SELECT version FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? AND source = \'_var_lib_dpkg_status_\';";
        case ZBDatabaseStatementTypeRemoteInstanceOfPackageWithVersion:
            return @"SELECT * FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? AND version = ? AND source != \'_var_lib_dpkg_status_\';";
        case ZBDatabaseStatementTypeIsPackageAvailable:
            return @"SELECT 1 FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? AND source != \'_var_lib_dpkg_status_\';";
        case ZBDatabaseStatementTypeIsPackageAvailableWithVersion:
            return @"SELECT 1 FROM " PACKAGES_TABLE_NAME " WHERE identifier = ? AND version = ? AND source != \'_var_lib_dpkg_status_\';";
        case ZBDatabaseStatementTypeSearchForPackageWithName:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE name LIKE ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.name;";
        case ZBDatabaseStatementTypeSearchForPackageWithDescription:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE description LIKE ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.name;";
        case ZBDatabaseStatementTypeSearchForPackageByAuthorName:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE authorName LIKE ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.name;";
        case ZBDatabaseStatementTypeSearchForPackageByAuthorNameAndEmail:
            return @"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE authorName = ? AND authorEmail = ? GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version ORDER BY p.name;";
        case ZBDatabaseStatementTypeRemovePackageWithUUID:
            return @"DELETE FROM " PACKAGES_TABLE_NAME " WHERE uuid = ?";
        case ZBDatabaseStatementTypeInsertPackage:
            return @"INSERT INTO " PACKAGES_TABLE_NAME "(authorName, description, downloadSize, iconURL, identifier, installedSize, lastSeen, name, role, section, source, tag, uuid, version, authorEmail, conflicts, depends, depictionURL, essential, filename, header, homepageURL, maintainerEmail, maintainerName, priority, provides, replaces, sha256) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
        case ZBDatabaseStatementTypeSources:
            return @"SELECT * FROM " SOURCES_TABLE_NAME ";";
        case ZBDatabaseStatementTypeSourceWithUUID:
            return @"SELECT * FROM " SOURCES_TABLE_NAME " WHERE uuid = ?;";
        case ZBDatabaseStatementTypeInsertSource:
            return @"INSERT INTO " SOURCES_TABLE_NAME "(architectures, archiveType, codename, components, distribution, label, origin, paymentEndpoint, sourceDescription, suite, supportsFeaturedPackages, url, uuid, version) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
        case ZBDatabaseStatementTypeSearchAuthorsByName:
            return @"SELECT DISTINCT authorName, authorEmail FROM " PACKAGES_TABLE_NAME " WHERE authorName LIKE ? OR authorEmail LIKE ?";
        case ZBDatabaseStatementTypeSectionReadout:
            return @"SELECT section, COUNT(DISTINCT identifier) from " PACKAGES_TABLE_NAME " WHERE source = ? GROUP BY section ORDER BY section";
        case ZBDatabaseStatementTypeSectionsReadout:
            return @"SELECT DISTINCT(section) from " PACKAGES_TABLE_NAME " ORDER BY section";
        case ZBDatabaseStatementTypePackagesInSourceCount:
            return @"SELECT COUNT(*) FROM (SELECT DISTINCT identifier FROM " PACKAGES_TABLE_NAME " WHERE source = ? GROUP BY IDENTIFIER);";
        case ZBDatabaseStatementTypeInstalledPackages:
            return @"SELECT p.identifier, p.source FROM (SELECT DISTINCT identifier, version FROM " PACKAGES_TABLE_NAME " WHERE source = \'_var_lib_dpkg_status_\') as i INNER JOIN " PACKAGES_TABLE_NAME " AS p ON i.identifier = p.identifier AND i.version = p.version WHERE p.source != \'_var_lib_dpkg_status_\'";
        default:
            return nil;
    }
}

- (sqlite3_stmt *)preparedStatementOfType:(ZBDatabaseStatementType)statementType {
    sqlite3_stmt *statement = preparedStatements[statementType];
    if (!statement) {
        const char *statementString = [self statementStringForStatementType:statementType].UTF8String;
        int result = sqlite3_prepare_v2(database, statementString, -1, &statement, NULL);
        if (result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to prepare sqlite statement %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        } else {
            preparedStatements[statementType] = statement;
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return statement;
}

- (int)initializePreparedStatements {
    preparedStatements = (sqlite3_stmt **) malloc(sizeof(sqlite3_stmt *) * ZBDatabaseStatementTypeCount);
    if (!preparedStatements) {
        ZBLog(@"[Zebra] Failed to allocate buffer for prepared statements");
        return SQLITE_NOMEM;
    } else {
        for (int i = 0; i < ZBDatabaseStatementTypeCount; i++) {
            preparedStatements[i] = NULL;
        }
    }
    
    return SQLITE_OK;
}

#pragma mark - Managing Transactions

- (int)beginTransaction {
    int result = sqlite3_exec(database, "BEGIN EXCLUSIVE TRANSACTION;", NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        ZBLog(@"[Zebra] Failed to begin transaction with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }
    return result;
}

- (int)endTransaction {
    int result = sqlite3_exec(database, "COMMIT;", NULL, NULL, NULL);
    if (result != SQLITE_OK) {
        ZBLog(@"[Zebra] Failed to commit transaction with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }
    return result;
}

- (void)performTransaction:(void (^)(void))transaction {
    @synchronized (self) {
        if ([self beginTransaction] != SQLITE_OK) return;
        transaction();
        [self endTransaction];
    }
}

#pragma mark - Package Retrieval

- (NSArray <ZBBasePackage *> *)packagesFromSource:(ZBSource *)source inSection:(NSString *)section {
    NSMutableArray *packages = [NSMutableArray new];
    sqlite3_stmt *statement;
    __block int result = SQLITE_OK;
    if (section) {
        statement = [self preparedStatementOfType:ZBDatabaseStatementTypePackagesFromSourceAndSection];
        result &= sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
        result &= sqlite3_bind_text(statement, 2, section.UTF8String, -1, SQLITE_TRANSIENT);
    } else {
        statement = [self preparedStatementOfType:ZBDatabaseStatementTypePackagesFromSource];
        result = sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
    }
    
    if (result != SQLITE_OK) return NULL;
    
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                if (package) [packages addObject:package];
            }
        } while (result == SQLITE_ROW);
            
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query packages from %@ with error %d (%s, %d)", source.uuid, result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];

    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    
    return packages;
}

- (ZBPackage *)packageWithUniqueIdentifier:(NSString *)uuid {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypePackagesWithUUID];
    int result = sqlite3_bind_text(statement, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    ZBPackage *package = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
        }
        
        if (result != SQLITE_OK && result != SQLITE_ROW) {
            ZBLog(@"[Zebra] Failed to query package with uuid with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return package;
}

- (NSArray <ZBPackage *> *)updatesForPackageList:(NSDictionary <NSString *,NSString *> *)packageList {
    NSMutableArray *updates = [NSMutableArray new];
    
    @synchronized (self) {
        [packageList enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull identifier, NSString * _Nonnull version, BOOL * _Nonnull stop) {
            if (![identifier containsString:@"gsc."] && ![identifier containsString:@"cy+"] && ![ZBSettings areUpdatesIgnoredForPackageIdentifier:identifier]) {
                NSString *highestVersion = [self highestVersionOfPackageIdentifier:identifier];
                if (![highestVersion isEqual:version]) {
                    ZBBasePackage *basePackage = [self basePackageWithIdentifier:identifier version:highestVersion];
                    if (basePackage) [updates addObject:basePackage];
                }
            }
        }];
    }
    
    return [updates sortedArrayUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)]]];
}

- (ZBBasePackage *)basePackageWithIdentifier:(NSString *)identifier version:(NSString *)version {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeBasePackageWithVersion];
    int result = sqlite3_bind_text(statement, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
    if (result == SQLITE_OK) {
        result = sqlite3_bind_text(statement, 2, version.UTF8String, -1, SQLITE_TRANSIENT);
    }
    
    if (result != SQLITE_OK) return NULL;
    
    ZBBasePackage *package = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            ZBBasePackage *basePackage = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
            if (basePackage) package = basePackage;
        }
        
        if (result != SQLITE_DONE && result != SQLITE_OK && result != SQLITE_ROW) {
            ZBLog(@"[Zebra] Failed to get version of package with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return package;
}

- (NSString *)highestVersionOfPackageIdentifier:(NSString *)packageIdentifier {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeHighestVersionOfPackage];
    int result = sqlite3_bind_text(statement, 1, packageIdentifier.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSString *highestVersion = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            const char *version = (const char *)sqlite3_column_text(statement, 0);
            if ((version && version[0] != '\0')) highestVersion = [NSString stringWithUTF8String:version];
        }
        
        if (result != SQLITE_DONE && result != SQLITE_OK && result != SQLITE_ROW) {
            ZBLog(@"[Zebra] Failed to get highest version of package with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return highestVersion;
}

- (ZBPackage *)installedInstanceOfPackage:(ZBPackage *)package {
    if ([package.source.uuid isEqualToString:@"_var_lib_dpkg_status"]) return package;
    
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeInstalledInstanceOfPackage];
    int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
        
    if (result != SQLITE_OK) return NULL;
    
    ZBPackage *installedInstance = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            installedInstance = [[ZBPackage alloc] initFromSQLiteStatement:statement];
        }
            
        if (result != SQLITE_DONE && result != SQLITE_OK && result != SQLITE_ROW) {
            ZBLog(@"[Zebra] Failed to get installed instance of package with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }

    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return installedInstance;
}

- (NSArray <ZBPackage *> *)latestPackages:(NSUInteger)limit {
    sqlite3_stmt *statement;
    __block int result = SQLITE_OK;
    if (limit == -1) {
        statement = [self preparedStatementOfType:ZBDatabaseStatementTypeLatestPackages];
    } else {
        statement = [self preparedStatementOfType:ZBDatabaseStatementTypeLatestPackagesWithLimit];
        result = sqlite3_bind_int(statement, 1, (int)limit);
    }

    if (result != SQLITE_OK) return NULL;
    
    NSMutableArray *results = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                
                if (package) [results addObject:package];
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query latest packages with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return results;
}

- (NSArray <ZBPackage *> *)packagesFromIdentifiers:(NSArray <NSString *> *)requestedPackages {
    if (!requestedPackages || !requestedPackages.count) return NULL;
    
    NSString *identifierString = [requestedPackages componentsJoinedByString:@"\', \'"];
    NSString *query = [NSString stringWithFormat:@"SELECT " BASE_PACKAGE_COLUMNS " FROM (SELECT identifier, maxversion(version) AS max_version FROM " PACKAGES_TABLE_NAME " WHERE identifier IN (\'%@\') GROUP BY identifier) as v INNER JOIN " PACKAGES_TABLE_NAME " AS p ON p.identifier = v.identifier AND p.version = v.max_version;", identifierString];
    sqlite3_stmt *statement;
    __block int result = sqlite3_prepare_v2(database, query.UTF8String, -1, &statement, nil);
        
    if (result != SQLITE_OK) return NULL;
    
    NSMutableArray *results = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                
                if (package) [results addObject:package];
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query packages from identifiers with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return results;
}

- (NSArray *)packagesWithReachableIcon:(int)limit excludeFrom:(NSArray <ZBSource *> *)blacklistedSources {
    NSMutableArray *packages = [NSMutableArray new];
    NSMutableArray *sourceUUIDs = [NSMutableArray arrayWithObject:@"_var_lib_dpkg_status_"];
        
    for (ZBSource *source in blacklistedSources) {
        [sourceUUIDs addObject:source.uuid];
    }
    NSString *excludeString = [NSString stringWithFormat:@"(%@)", [sourceUUIDs componentsJoinedByString:@", "]];
    NSString *query = [NSString stringWithFormat:@"SELECT * FROM PACKAGES WHERE SOURCE NOT IN %@ AND ICON IS NOT NULL ORDER BY RANDOM() LIMIT %d;", excludeString, limit];
    
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, [query UTF8String], -1, &statement, nil) == SQLITE_OK) {
        @synchronized (self) {
            while (sqlite3_step(statement) == SQLITE_ROW) {
                ZBPackage *package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
                if (package) [packages addObject:package];
            }
        }
    }
    
    sqlite3_finalize(statement);
    return packages;
}

- (NSArray <NSString *> *)allVersionsOfPackage:(ZBPackage *)package {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeAllVersionsOfPackages];
    __block int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSMutableArray *versions = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *version = (const char *)sqlite3_column_text(statement, 0);
                if (version) [versions addObject:[NSString stringWithUTF8String:version]];
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE && result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to get all versions of package with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
        
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return versions;
}

- (NSArray <ZBPackage *> *)allInstancesOfPackage:(ZBPackage *)package {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeAllInstancesOfPackage];
    __block int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSMutableArray *packages = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                if (package) [packages addObject:package];
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE && result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to get all instances of package with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
        
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packages;
}

- (NSDictionary <NSString *,NSString *> *)installedPackages {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeInstalledPackages];

    NSMutableDictionary *installedPackages = [NSMutableDictionary new];
    @synchronized (self) {
        int result = SQLITE_OK;
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *identifier = (const char *)sqlite3_column_text(statement, 0);
                const char *source = (const char *)sqlite3_column_text(statement, 1);

                if (identifier && source) {
                    [installedPackages setObject:[NSString stringWithUTF8String:source] forKey:[NSString stringWithUTF8String:identifier]];
                }
            }
        } while (result == SQLITE_ROW);

        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query installed packages with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }

    sqlite3_reset(statement);
    return installedPackages;
}

#pragma mark - Package Information

- (NSString *)installedVersionOfPackage:(ZBPackage *)package {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeInstalledVersionOfPackage];
    int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
        
    if (result != SQLITE_OK) return NULL;
        
    NSString *installedVersion = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            const char *version = (const char *)sqlite3_column_text(statement, 0);
            if (version) {
                installedVersion = [NSString stringWithUTF8String:version];
            }
        }
    }
            
    if (result != SQLITE_DONE && result != SQLITE_OK && result != SQLITE_ROW) {
        ZBLog(@"[Zebra] Failed to get installed version of package with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }
        
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return installedVersion;
}

- (ZBPackage *)remoteInstanceOfPackage:(ZBPackage *)package withVersion:(NSString *)version {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeRemoteInstanceOfPackageWithVersion];
    int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
    result &= sqlite3_bind_text(statement, 2, version.UTF8String, -1, SQLITE_TRANSIENT);
        
    if (result != SQLITE_OK) return NULL;
    
    ZBPackage *packageWithVersion = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            ZBPackage *package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
            if (package) packageWithVersion = package;
        }
    }
        
    if (result != SQLITE_DONE && result != SQLITE_OK && result != SQLITE_ROW) {
        ZBLog(@"[Zebra] Failed to get installed version of package with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }
        
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packageWithVersion;
}

- (NSArray <ZBPackage *> *)allRemoteInstancesOfPackage:(ZBPackage *)package withVersion:(NSString *)version {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeRemoteInstanceOfPackageWithVersion];
    __block int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
    result &= sqlite3_bind_text(statement, 2, version.UTF8String, -1, SQLITE_TRANSIENT);

    if (result != SQLITE_OK) return NULL;

    NSMutableArray *packages = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBPackage *package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
                if (package) [packages addObject:package];
            }
        } while (result == SQLITE_ROW);

        if (result != SQLITE_DONE && result != SQLITE_OK) {
            ZBLog(@"[Zebra] Failed to get all remote instances of package with version got error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];

    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packages;
}

- (BOOL)isPackageAvailable:(ZBPackage *)package checkVersion:(BOOL)checkVersion; {
    if (package.source.remote) return YES;
    
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeIsPackageAvailable + checkVersion];
    int result = sqlite3_bind_text(statement, 1, package.identifier.UTF8String, -1, SQLITE_TRANSIENT);
    if (checkVersion) result &= sqlite3_bind_text(statement, 2, package.version.UTF8String, -1, SQLITE_TRANSIENT);
        
    if (result != SQLITE_OK) return NO;
    
    BOOL isAvailable = NO;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) isAvailable = YES;
    }
        
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return isAvailable;
}

#pragma mark - Package Searching

- (NSArray <ZBPackage *> *)filterDuplicatesOfInstalledPackages:(NSArray <ZBPackage *> *)packages {
    NSMutableDictionary <NSString *, ZBPackage *> *filter = [NSMutableDictionary new];
    for (ZBPackage *package in packages) {
        ZBPackage *existingPackage = filter[package.identifier];
        if (existingPackage) {
            // package and existingPackage are the same packages, one is installed, another is generic
            // If a package added to a temporary list is installed (source = var_lib_dpkg_status_), we discard them and replace with its counterpart which contains more properties for managing packages
            if ([existingPackage isInstalled]) {
                filter[existingPackage.identifier] = package;
            }
        } else {
            filter[package.identifier] = package;
        }
    }
    return [filter allValues];
}

- (void)searchForPackagesByName:(NSString *)name completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    if (currentSearchBlock) {
        dispatch_block_cancel(currentSearchBlock);
    }
    
    __block dispatch_block_t searchBlock = dispatch_block_create(0, ^{
        sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSearchForPackageWithName];
        
        const char *filter = [NSString stringWithFormat:@"%%%@%%", name].UTF8String;
        int result = sqlite3_bind_text(statement, 1, filter, -1, SQLITE_TRANSIENT);
        
        NSMutableArray *packages = [NSMutableArray new];
        if (result == SQLITE_OK) {
            do {
                result = sqlite3_step(statement);
                if (result == SQLITE_ROW) {
                    ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                    if (package) [packages addObject:package];
                }
            } while (result == SQLITE_ROW && !dispatch_block_testcancel(searchBlock));
            
            if (result != SQLITE_DONE) {
                ZBLog(@"[Zebra] Failed to search for packages with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
            }
        } else {
            ZBLog(@"[Zebra] Failed to initialize search query with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
        
        sqlite3_clear_bindings(statement);
        sqlite3_reset(statement);
        
        if (!dispatch_block_testcancel(searchBlock)) {
            completion([self filterDuplicatesOfInstalledPackages:packages]);
        }
    });
    
    currentSearchBlock = searchBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), searchQueue, searchBlock);
}

- (void)searchForPackagesByDescription:(NSString *)description completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    if (currentSearchBlock) {
        dispatch_block_cancel(currentSearchBlock);
    }
    
    __block dispatch_block_t searchBlock = dispatch_block_create(0, ^{
        sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSearchForPackageWithDescription];
        
        const char *filter = [NSString stringWithFormat:@"%%%@%%", description].UTF8String;
        int result = sqlite3_bind_text(statement, 1, filter, -1, SQLITE_TRANSIENT);
        
        NSMutableArray *packages = [NSMutableArray new];
        if (result == SQLITE_OK) {
            do {
                result = sqlite3_step(statement);
                if (result == SQLITE_ROW) {
                    ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                    if (package) [packages addObject:package];
                }
            } while (result == SQLITE_ROW && !dispatch_block_testcancel(searchBlock));
            
            if (result != SQLITE_DONE) {
                ZBLog(@"[Zebra] Failed to search for packages with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
            }
        } else {
            ZBLog(@"[Zebra] Failed to initialize search query with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
        
        sqlite3_clear_bindings(statement);
        sqlite3_reset(statement);
        
        if (!dispatch_block_testcancel(searchBlock)) {
            completion([self filterDuplicatesOfInstalledPackages:packages]);
        }
    });
    
    currentSearchBlock = searchBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), searchQueue, searchBlock);
}

- (void)searchForPackagesByAuthorWithName:(NSString *)name email:(NSString *_Nullable)email completion:(void (^)(NSArray <ZBPackage *> *packages))completion {
    if (currentSearchBlock) {
        dispatch_block_cancel(currentSearchBlock);
    }
    
    __block dispatch_block_t searchBlock = dispatch_block_create(0, ^{
        sqlite3_stmt *statement = [self preparedStatementOfType:email
                                ? ZBDatabaseStatementTypeSearchForPackageByAuthorNameAndEmail
                                : ZBDatabaseStatementTypeSearchForPackageByAuthorName];
        
        const char *filter = email ? name.UTF8String : [NSString stringWithFormat:@"%%%@%%", name].UTF8String;
        int result = sqlite3_bind_text(statement, 1, filter, -1, SQLITE_TRANSIENT);
        if (result == SQLITE_OK && email)
            result = sqlite3_bind_text(statement, 2, email.UTF8String, -1, SQLITE_TRANSIENT);
        
        NSMutableArray *packages = [NSMutableArray new];
        if (result == SQLITE_OK) {
            do {
                result = sqlite3_step(statement);
                if (result == SQLITE_ROW) {
                    ZBBasePackage *package = [[ZBBasePackage alloc] initFromSQLiteStatement:statement];
                    if (package) [packages addObject:package];
                }
            } while (result == SQLITE_ROW && !dispatch_block_testcancel(searchBlock));
            
            if (result != SQLITE_DONE) {
                ZBLog(@"[Zebra] Failed to search for packages with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
            }
        } else {
            ZBLog(@"[Zebra] Failed to initialize search query with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
        
        sqlite3_clear_bindings(statement);
        sqlite3_reset(statement);
        
        if (!dispatch_block_testcancel(searchBlock)) {
            completion([self filterDuplicatesOfInstalledPackages:packages]);
        }
    });
    
    currentSearchBlock = searchBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), searchQueue, searchBlock);
}

#pragma mark - Source Retrieval

- (NSSet <ZBSource *> *)sources {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSources];
    
    NSMutableSet *sources = [NSMutableSet new];
    @synchronized (self) {
        int result = SQLITE_OK;
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                ZBSource *source = [[ZBSource alloc] initWithSQLiteStatement:statement];
                if (source) [sources addObject:source];
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query sources with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_reset(statement);
    return sources;
}

- (ZBSource *)sourceWithUUID:(NSString *)uuid {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSourceWithUUID];
    int result = sqlite3_bind_text(statement, 1, uuid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    ZBSource *source = NULL;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            source = [[ZBSource alloc] initWithSQLiteStatement:statement];
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return source;
}

#pragma mark - Source Information

- (NSDictionary *)packageListFromSource:(ZBSource *)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypePackageListFromSource];
    __block int result = sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSMutableDictionary *packageList = [NSMutableDictionary new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *identifierChars = (const char *)sqlite3_column_text(statement, 0);
                const char *versionChars = (const char *)sqlite3_column_text(statement, 1);
                if ((identifierChars && identifierChars[0] != '\0') && (versionChars && versionChars[0] != '\0')) {
                    NSString *identifier = [NSString stringWithUTF8String:identifierChars];
                    NSString *version = [NSString stringWithUTF8String:versionChars];
                    if (identifier && version) packageList[identifier] = version;
                }
            }
        } while (result == SQLITE_ROW);
    }];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packageList;
}

- (NSDictionary *)virtualPackageListFromSource:(ZBSource *)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeVirtualPackageListFromSource];
    __block int result = sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSMutableDictionary *packageList = [NSMutableDictionary new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *provides = (const char *)sqlite3_column_text(statement, 0);
                if (provides) {
                    NSArray *allProvides = [[NSString stringWithUTF8String:provides] componentsSeparatedByString:@","];
                    for (NSString *virtualPackage in allProvides) {
                        NSArray *components = [ZBDependencyResolver separateVersionComparison:virtualPackage];
                        packageList[components[0]] = components[2];
                    }
                }
            }
        } while (result == SQLITE_ROW);
    }];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packageList;
}


- (NSSet *)uniqueIdentifiersForPackagesFromSource:(ZBBaseSource *)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeUUIDsFromSource];
    __block int result = sqlite3_bind_text(statement, 1, [source.uuid UTF8String], -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return NULL;
    
    NSMutableSet *uuids = [NSMutableSet new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *uuid = (const char *)sqlite3_column_text(statement, 0);
                if (uuid) {
                    [uuids addObject:[NSString stringWithUTF8String:uuid]];
                }
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query package uuids from %@ with error %d (%s, %d)", source.uuid, result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];

    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return uuids;
}

- (NSUInteger)numberOfPackagesInSource:(ZBSource *)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypePackagesInSourceCount];
    int result = sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
    
    if (result != SQLITE_OK) return -1;
    
    NSUInteger packageCount = 0;
    @synchronized (self) {
        result = sqlite3_step(statement);
        if (result == SQLITE_ROW) {
            packageCount = sqlite3_column_int(statement, 0);
        }
        
        if (result != SQLITE_OK && result != SQLITE_ROW) {
            ZBLog(@"[Zebra] Failed to obtain package count from source with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return packageCount;
}

- (NSArray <NSString *> *)sectionsReadout {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSectionsReadout];
    __block int result = SQLITE_OK;
    
    NSMutableArray *sections = [NSMutableArray new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *section = (const char *)sqlite3_column_text(statement, 0);
                if (section) {
                    [sections addObject:[NSString stringWithUTF8String:section]];
                }
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query all sections with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return sections;
}

- (NSDictionary <NSString *, NSNumber *> *)sectionReadoutForSource:(ZBSource *)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSectionReadout];
    __block int result = sqlite3_bind_text(statement, 1, source.uuid.UTF8String, -1, SQLITE_TRANSIENT);
        
    if (result != SQLITE_OK) return NULL;
    
    NSMutableDictionary *sectionReadout = [NSMutableDictionary new];
    [self performTransaction:^{
        do {
            result = sqlite3_step(statement);
            if (result == SQLITE_ROW) {
                const char *section = (const char *)sqlite3_column_text(statement, 0);
                if (section) {
                    int packageCount = sqlite3_column_int(statement, 1);
                    sectionReadout[[NSString stringWithUTF8String:section]] = @(packageCount);
                }
            }
        } while (result == SQLITE_ROW);
        
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to query section readout with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
    }];
            
    sectionReadout[@"Uncategorized"] = sectionReadout[@""];
    [sectionReadout removeObjectForKey:@""];
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    return sectionReadout;
}

#pragma mark - Package Management

- (void)insertPackage:(char **)package {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeInsertPackage];
    
    sqlite3_bind_text(statement, ZBPackageColumnIdentifier + 1, package[ZBPackageColumnIdentifier], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnName + 1, package[ZBPackageColumnName], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnVersion + 1, package[ZBPackageColumnVersion], -1, SQLITE_TRANSIENT);
    
    char *author = package[ZBPackageColumnAuthorName];
    char *emailBegin = strchr(author, '<');
    char *emailEnd = strchr(author, '>');
    if (emailBegin && emailEnd) {
        char *email = (char *)malloc(emailEnd - emailBegin);
        memcpy(email, emailBegin + 1, emailEnd - emailBegin - 1);
        email[emailEnd - emailBegin - 1] = 0;
        
        if (author < emailBegin && *(emailBegin - 1) == ' ') {
            emailBegin--;
        }
        *emailBegin = 0;
        
        if (strcmp(author, "") == 0) { // If somehow the package maintainer messed up the email...
            strcpy(author, email);
        }
        sqlite3_bind_text(statement, ZBPackageColumnAuthorName + 1, author, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, ZBPackageColumnAuthorEmail + 1, email, -1, SQLITE_TRANSIENT);
        free(email);
    } else {
        sqlite3_bind_text(statement, ZBPackageColumnAuthorName + 1, author, -1, SQLITE_TRANSIENT);
        sqlite3_bind_null(statement, ZBPackageColumnAuthorEmail + 1);
    }
    
    sqlite3_bind_text(statement, ZBPackageColumnConflicts + 1, package[ZBPackageColumnConflicts], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnDepends + 1, package[ZBPackageColumnDepends], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnDepictionURL + 1, package[ZBPackageColumnDepictionURL], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(statement, ZBPackageColumnDownloadSize + 1, atoi(package[ZBPackageColumnDownloadSize]));
    //    package.essential = packageDictionary[@"Essential"];
    sqlite3_bind_text(statement, ZBPackageColumnFilename + 1, package[ZBPackageColumnFilename], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnHomepageURL + 1, package[ZBPackageColumnHomepageURL], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnIconURL + 1, package[ZBPackageColumnIconURL], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(statement, ZBPackageColumnInstalledSize + 1, atoi(package[ZBPackageColumnInstalledSize]));
    
    char *maintainer = package[ZBPackageColumnMaintainerName];
    emailBegin = strchr(maintainer, '<');
    emailEnd = strchr(maintainer, '>');
    if (emailBegin && emailEnd) {
        char *email = (char *)malloc(emailEnd - emailBegin);
        memcpy(email, emailBegin + 1, emailEnd - emailBegin - 1);
        email[emailEnd - emailBegin - 1] = 0;
        
        if (maintainer < emailBegin && *(emailBegin - 1) == ' ') {
            emailBegin--;
        }
        *emailBegin = 0;
        
        if (strcmp(maintainer, "") == 0) { // If somehow the package maintainer messed up the email...
            strcpy(maintainer, email);
        }
        sqlite3_bind_text(statement, ZBPackageColumnMaintainerName + 1, author, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, ZBPackageColumnMaintainerEmail + 1, email, -1, SQLITE_TRANSIENT);
        free(email);
    } else {
        sqlite3_bind_text(statement, ZBPackageColumnMaintainerName + 1, maintainer, -1, SQLITE_TRANSIENT);
        sqlite3_bind_null(statement, ZBPackageColumnMaintainerEmail + 1);
    }
    
    sqlite3_bind_text(statement, ZBPackageColumnDescription + 1, package[ZBPackageColumnDescription], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnPriority + 1, package[ZBPackageColumnPriority], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnProvides + 1, package[ZBPackageColumnProvides], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnReplaces + 1, package[ZBPackageColumnReplaces], -1, SQLITE_TRANSIENT);
    
    int roleValue = 0;
    char *tag = package[ZBPackageColumnTag];
    if (tag && tag[0] != '\0') {
        char *roleTag = strstr(tag, "role::");
        if (roleTag) {
            char *begin = roleTag + 6;
            char *end = strchr(roleTag, ',') ?: strchr(roleTag, '\0');
            
            size_t size = end - begin;
            char *role = malloc(size + 1 * sizeof(char));
            strncpy(role, begin, size);
            role[size] = '\0';
            
            if (strcmp(role, "user") == 0 || strcmp(role, "enduser") == 0) roleValue = 0;
            else if (strcmp(role, "hacker") == 0) roleValue = 1;
            else if (strcmp(role, "developer") == 0) roleValue = 2;
            else if (strcmp(role, "cydia") == 0 || strcmp(role, "goddess") == 0) roleValue = 3;
            else roleValue = 0;
            
            free(role);
        }
    }
    sqlite3_bind_int(statement, ZBPackageColumnRole + 1, roleValue);
    
    sqlite3_bind_text(statement, ZBPackageColumnSection + 1, package[ZBPackageColumnSection], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnSHA256 + 1, package[ZBPackageColumnSHA256], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnTag + 1, package[ZBPackageColumnTag], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnVersion + 1, package[ZBPackageColumnVersion], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnSource + 1, package[ZBPackageColumnSource], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBPackageColumnUUID + 1, package[ZBPackageColumnUUID], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement, ZBPackageColumnLastSeen + 1, *(int *)package[ZBPackageColumnLastSeen]);
    
    int result = sqlite3_step(statement);
    if (result != SQLITE_DONE) {
        ZBLog(@"[Zebra] Failed to insert package into database with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
}

- (void)deletePackagesWithUniqueIdentifiers:(NSSet *)uniqueIdentifiers {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeRemovePackageWithUUID];
    
    [self performTransaction:^{
        for (NSString *uuid in uniqueIdentifiers) {
            int result = sqlite3_bind_text(statement, 1, [uuid UTF8String], -1, SQLITE_TRANSIENT);
            if (result == SQLITE_OK) {
                result = sqlite3_step(statement);
                if (result != SQLITE_DONE) {
                    ZBLog(@"[Zebra] Failed to delete package with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
                }
            }
            sqlite3_clear_bindings(statement);
            sqlite3_reset(statement);
        }
    }];
}

#pragma mark - Source Management

- (ZBSource *)insertSource:(char **)source {
    sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeInsertSource];
    
    sqlite3_bind_text(statement, ZBSourceColumnArchitectures + 1, source[ZBSourceColumnArchitectures], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnArchiveType + 1, source[ZBSourceColumnArchiveType], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnCodename + 1, source[ZBSourceColumnCodename], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnComponents + 1, source[ZBSourceColumnComponents], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnDistribution + 1, source[ZBSourceColumnDistribution], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnLabel + 1, source[ZBSourceColumnLabel], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnOrigin + 1, source[ZBSourceColumnOrigin], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnPaymentEndpoint + 1, source[ZBSourceColumnPaymentEndpoint], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnDescription + 1, source[ZBSourceColumnDescription], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnSuite + 1, source[ZBSourceColumnSuite], -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(statement, ZBSourceColumnSupportsFeaturedPackages + 1, *(int *)source[ZBSourceColumnSupportsFeaturedPackages]);
    sqlite3_bind_text(statement, ZBSourceColumnURL + 1, source[ZBSourceColumnURL], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnUUID + 1, source[ZBSourceColumnUUID], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, ZBSourceColumnVersion + 1, source[ZBSourceColumnVersion], -1, SQLITE_TRANSIENT);
    
    @synchronized (self) {
        int result = sqlite3_step(statement);
        if (result != SQLITE_DONE) {
            ZBLog(@"[Zebra] Failed to insert source into database with error %d (%s, %d)", result, sqlite3_errmsg(database), sqlite3_extended_errcode(database));
        }
    }
    
    sqlite3_clear_bindings(statement);
    sqlite3_reset(statement);
    
    NSString *uuid = [NSString stringWithUTF8String:source[ZBSourceColumnUUID]];
    return [self sourceWithUUID:uuid];
}

- (void)updateURIForSource:(ZBSource *)source {
    
}

- (void)deleteSource:(ZBSource *)source {
    @synchronized (self) {
        const char *sourceDeleteQuery = [NSString stringWithFormat:@"DELETE FROM " SOURCES_TABLE_NAME " WHERE uuid = \'%@\'", source.uuid].UTF8String;
        sqlite3_exec(self->database, sourceDeleteQuery, nil, nil, nil);
        
        const char *packageDeleteQuery = [NSString stringWithFormat:@"DELETE FROM " PACKAGES_TABLE_NAME " WHERE source = \'%@\'", source.uuid].UTF8String;
        sqlite3_exec(self->database, packageDeleteQuery, nil, nil, nil);
    }
}

#pragma mark - Package Author

- (void)searchForAuthorsByNameOrEmail:(NSString *)nameOrEmail completion:(void (^)(NSArray <NSArray <NSString *> *> *authors))completion {
    if (currentSearchBlock) {
        dispatch_block_cancel(currentSearchBlock);
    }
    
    __block dispatch_block_t searchBlock = dispatch_block_create(0, ^{
        sqlite3_stmt *statement = [self preparedStatementOfType:ZBDatabaseStatementTypeSearchAuthorsByName];
        
        const char *filter = [NSString stringWithFormat:@"%%%@%%", nameOrEmail].UTF8String;
        int result = sqlite3_bind_text(statement, 1, filter, -1, SQLITE_TRANSIENT);
        result = result == SQLITE_OK ? sqlite3_bind_text(statement, 2, filter, -1, SQLITE_TRANSIENT) : result;
        
        NSMutableArray *authors = [NSMutableArray new];
        if (result == SQLITE_OK) {
            do {
                result = sqlite3_step(statement);
                if (result == SQLITE_ROW) {
                    const char *authorName = (const char *)sqlite3_column_text(statement, 0);
                    const char *authorEmail = (const char *)sqlite3_column_text(statement, 1);
                    if ((authorName && strlen(authorName)) || (authorEmail && strlen(authorEmail))) {
                        [authors addObject:[NSArray arrayWithObjects:[NSString stringWithCString:authorName ?: "" encoding:NSUTF8StringEncoding], [NSString stringWithCString:authorEmail ?: "" encoding:NSUTF8StringEncoding], nil]];
                    }
                }
            } while (result == SQLITE_ROW && !dispatch_block_testcancel(searchBlock));
            
            if (result != SQLITE_DONE) {
                ZBLog(@"[Zebra] Failed to search for authors with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
            }
        } else {
            ZBLog(@"[Zebra] Failed to initialize search query with error %d (%s, %d)", result, sqlite3_errmsg(self->database), sqlite3_extended_errcode(self->database));
        }
        
        sqlite3_clear_bindings(statement);
        sqlite3_reset(statement);
        
        if (!dispatch_block_testcancel(searchBlock)) {
            completion(authors);
        }
    });
    
    currentSearchBlock = searchBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), searchQueue, searchBlock);
}

#pragma mark - Dependency Resolution

- (ZBPackage * _Nullable)packageThatProvides:(NSString *)identifier thatSatisfiesComparison:(NSString *)comparison ofVersion:(NSString *)version {
    return [self packageThatProvides:identifier thatSatisfiesComparison:comparison ofVersion:version thatIsNot:NULL];
}

- (ZBPackage * _Nullable)packageThatProvides:(NSString *)packageIdentifier thatSatisfiesComparison:(NSString *)comparison ofVersion:(NSString *)version thatIsNot:(ZBPackage * _Nullable)exclude {
    packageIdentifier = [packageIdentifier lowercaseString];
    
    const char *query;
    const char *firstSearchTerm = [[NSString stringWithFormat:@"%%, %@ (%%", packageIdentifier] UTF8String];
    const char *secondSearchTerm = [[NSString stringWithFormat:@"%%, %@, %%", packageIdentifier] UTF8String];
    const char *thirdSearchTerm = [[NSString stringWithFormat:@"%@ (%%", packageIdentifier] UTF8String];
    const char *fourthSearchTerm = [[NSString stringWithFormat:@"%@, %%", packageIdentifier] UTF8String];
    const char *fifthSearchTerm = [[NSString stringWithFormat:@"%%, %@", packageIdentifier] UTF8String];
    const char *sixthSearchTerm = [[NSString stringWithFormat:@"%%| %@", packageIdentifier] UTF8String];
    const char *seventhSearchTerm = [[NSString stringWithFormat:@"%%, %@ |%%", packageIdentifier] UTF8String];
    const char *eighthSearchTerm = [[NSString stringWithFormat:@"%@ |%%", packageIdentifier] UTF8String];
    
    if (exclude) {
        query = "SELECT * FROM PACKAGES WHERE IDENTIFIER != ? AND SOURCE != \'_var_lib_dpkg_status_\' AND (PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ?) AND SOURCE != \'_var_lib_dpkg_status_\' LIMIT 1;";
    }
    else {
        query = "SELECT * FROM PACKAGES WHERE SOURCE != \'_var_lib_dpkg_status_\' AND (PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ?) LIMIT 1;";
    }
    
    NSMutableArray <ZBPackage *> *packages = [NSMutableArray new];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK) {
        if (exclude) {
            sqlite3_bind_text(statement, 1, [packageIdentifier UTF8String], -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_text(statement, exclude ? 2 : 1, firstSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 3 : 2, secondSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 4 : 3, thirdSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 5 : 4, fourthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 6 : 5, fifthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 7 : 6, sixthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 8 : 7, seventhSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 9 : 8, eighthSearchTerm, -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *providesLine = (const char *)sqlite3_column_text(statement, ZBPackageColumnProvides);
            if (providesLine != 0) {
                NSString *provides = [[NSString stringWithUTF8String:providesLine] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSArray *virtualPackages = [provides componentsSeparatedByString:@","];
                
                for (NSString *virtualPackage in virtualPackages) {
                    NSArray *versionComponents = [ZBDependencyResolver separateVersionComparison:[virtualPackage stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
                    if ([versionComponents[0] isEqualToString:packageIdentifier] &&
                        ([versionComponents[2] isEqualToString:@"0:0"] || [ZBDependencyResolver doesVersion:versionComponents[2] satisfyComparison:comparison ofVersion:version])) {
                        ZBPackage *package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
                        [packages addObject:package];
                        break;
                    }
                }
            }
        }
    }
    sqlite3_finalize(statement);
    
    return [packages count] ? packages[0] : NULL; //Returns the first package in the array, we could use interactive dependency resolution in the future
}

- (ZBPackage * _Nullable)installedPackageThatProvides:(NSString *)identifier thatSatisfiesComparison:(NSString *)comparison ofVersion:(NSString *)version {
    return [self installedPackageThatProvides:identifier thatSatisfiesComparison:comparison ofVersion:version thatIsNot:NULL];
}

- (ZBPackage * _Nullable)installedPackageThatProvides:(NSString *)packageIdentifier thatSatisfiesComparison:(NSString *)comparison ofVersion:(NSString *)version thatIsNot:(ZBPackage *_Nullable)exclude {
    const char *query;
    const char *firstSearchTerm = [[NSString stringWithFormat:@"%%, %@ (%%", packageIdentifier] UTF8String];
    const char *secondSearchTerm = [[NSString stringWithFormat:@"%%, %@, %%", packageIdentifier] UTF8String];
    const char *thirdSearchTerm = [[NSString stringWithFormat:@"%@ (%%", packageIdentifier] UTF8String];
    const char *fourthSearchTerm = [[NSString stringWithFormat:@"%@, %%", packageIdentifier] UTF8String];
    const char *fifthSearchTerm = [[NSString stringWithFormat:@"%%, %@", packageIdentifier] UTF8String];
    const char *sixthSearchTerm = [[NSString stringWithFormat:@"%%| %@", packageIdentifier] UTF8String];
    const char *seventhSearchTerm = [[NSString stringWithFormat:@"%%, %@ |%%", packageIdentifier] UTF8String];
    const char *eighthSearchTerm = [[NSString stringWithFormat:@"%@ |%%", packageIdentifier] UTF8String];
    
    if (exclude) {
        query = "SELECT * FROM PACKAGES WHERE IDENTIFIER != ? AND SOURCE = \'_var_lib_dpkg_status_\' AND (PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ?) LIMIT 1;";
    }
    else {
        query = "SELECT * FROM PACKAGES WHERE SOURCE = \'_var_lib_dpkg_status_\' AND (PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ?) LIMIT 1;";
    }
    
    NSMutableArray <ZBPackage *> *packages = [NSMutableArray new];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK) {
        if (exclude) {
            sqlite3_bind_text(statement, 1, [packageIdentifier UTF8String], -1, SQLITE_TRANSIENT);
        }
        sqlite3_bind_text(statement, exclude ? 2 : 1, firstSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 3 : 2, secondSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 4 : 3, thirdSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 5 : 4, fourthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 6 : 5, fifthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 7 : 6, sixthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 8 : 7, seventhSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, exclude ? 9 : 8, eighthSearchTerm, -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(statement) == SQLITE_ROW) {
            ZBPackage *package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
            [packages addObject:package];
        }
    }
    sqlite3_finalize(statement);
    
    for (ZBPackage *package in packages) {
        //If there is a comparison and a version then we return the first package that satisfies this comparison, otherwise we return the first package we see
        //(this also sets us up better later for interactive dependency resolution)
        if (comparison && version && [ZBDependencyResolver doesPackage:package satisfyComparison:comparison ofVersion:version]) {
            return package;
        }
        else if (!comparison || !version) {
            return package;
        }
    }
    
    return NULL;
}

- (ZBPackage * _Nullable)packageForIdentifier:(NSString *)identifier thatSatisfiesComparison:(NSString * _Nullable)comparison ofVersion:(NSString * _Nullable)version {
    return [self packageForIdentifier:identifier thatSatisfiesComparison:comparison ofVersion:version includeVirtualPackages:YES];
}

- (ZBPackage * _Nullable)packageForIdentifier:(NSString *)identifier thatSatisfiesComparison:(NSString * _Nullable)comparison ofVersion:(NSString * _Nullable)version includeVirtualPackages:(BOOL)checkVirtual {
    ZBPackage *package = nil;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, "SELECT * FROM PACKAGES WHERE IDENTIFIER = ? COLLATE NOCASE AND SOURCE != \'_var_lib_dpkg_status_\' LIMIT 1;", -1, &statement, nil) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, [identifier UTF8String], -1, SQLITE_TRANSIENT);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
            break;
        }
    }
    sqlite3_finalize(statement);
    
    // Only try to resolve "Provides" if we can't resolve the normal package.
    if (checkVirtual && package == NULL) {
        package = [self packageThatProvides:identifier thatSatisfiesComparison:comparison ofVersion:version]; //there is a scenario here where two packages that provide a package could be found (ex: anemone, snowboard, and ithemer all provide winterboard) we need to ask the user which one to pick.
    }
    
    if (package != NULL) {
        NSArray *otherVersions = [self allInstancesOfPackage:package];
        NSSortDescriptor* sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:nil ascending:NO selector:@selector(compare:)];
        otherVersions = [otherVersions sortedArrayUsingDescriptors:@[sortDescriptor]];
        
        if (version != NULL && comparison != NULL) {
            if ([otherVersions count] > 1) {
                for (ZBPackage *package in otherVersions) {
                    if ([ZBDependencyResolver doesPackage:package satisfyComparison:comparison ofVersion:version]) {
                        return package;
                    }
                }
                
                return NULL;
            }
            return [ZBDependencyResolver doesPackage:otherVersions[0] satisfyComparison:comparison ofVersion:version] ? otherVersions[0] : NULL;
        }
        return otherVersions[0];
    }

    return NULL;
}

- (ZBPackage * _Nullable)installedPackageForIdentifier:(NSString *)identifier thatSatisfiesComparison:(NSString * _Nullable)comparison ofVersion:(NSString * _Nullable)version {
    return [self installedPackageForIdentifier:identifier thatSatisfiesComparison:comparison ofVersion:version includeVirtualPackages:YES thatIsNot:NULL];
}

- (ZBPackage * _Nullable)installedPackageForIdentifier:(NSString *)identifier thatSatisfiesComparison:(NSString * _Nullable)comparison ofVersion:(NSString * _Nullable)version includeVirtualPackages:(BOOL)checkVirtual {
    return [self installedPackageForIdentifier:identifier thatSatisfiesComparison:comparison ofVersion:version includeVirtualPackages:checkVirtual thatIsNot:NULL];
}

- (ZBPackage * _Nullable)installedPackageForIdentifier:(NSString *)identifier thatSatisfiesComparison:(NSString * _Nullable)comparison ofVersion:(NSString * _Nullable)version includeVirtualPackages:(BOOL)checkVirtual thatIsNot:(ZBPackage *_Nullable)exclude {
    NSString *query;
    if (exclude) {
        query = [NSString stringWithFormat:@"SELECT * FROM PACKAGES WHERE IDENTIFIER = \'%@\' COLLATE NOCASE AND SOURCE = \'_var_lib_dpkg_status_\' AND PACKAGE != \'%@\' LIMIT 1;", identifier, [exclude identifier]];
    }
    else {
        query = [NSString stringWithFormat:@"SELECT * FROM PACKAGES WHERE IDENTIFIER = \'%@\' COLLATE NOCASE AND SOURCE = \'_var_lib_dpkg_status_\' LIMIT 1;", identifier];
    }
    
    ZBPackage *package;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, [query UTF8String], -1, &statement, nil) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            package = [[ZBPackage alloc] initFromSQLiteStatement:statement];
            break;
        }
    }
    sqlite3_finalize(statement);
    
    // Only try to resolve "Provides" if we can't resolve the normal package.
    if (checkVirtual && package == NULL) {
        package = [self installedPackageThatProvides:identifier thatSatisfiesComparison:comparison ofVersion:version thatIsNot:exclude]; //there is a scenario here where two packages that provide a package could be found (ex: anemone, snowboard, and ithemer all provide winterboard) we need to ask the user which one to pick.
    }
    
    if (package != NULL) {
        if (version != NULL && comparison != NULL) {
            return [ZBDependencyResolver doesPackage:package satisfyComparison:comparison ofVersion:version] ? package : NULL;
        }
        return package;
    }
    
    return NULL;
}

- (NSArray <ZBPackage *> * _Nullable)packagesThatDependOn:(ZBPackage *)package {
    return [self packagesThatDependOnPackageIdentifier:[package identifier] removedPackage:package];
}

- (NSArray <ZBPackage *> * _Nullable)packagesThatDependOnPackageIdentifier:(NSString *)packageIdentifier removedPackage:(ZBPackage *)package {
    NSMutableArray *packages = [NSMutableArray new];
    
    const char *firstSearchTerm = [[NSString stringWithFormat:@"%%, %@ (%%", packageIdentifier] UTF8String];
    const char *secondSearchTerm = [[NSString stringWithFormat:@"%%, %@, %%", packageIdentifier] UTF8String];
    const char *thirdSearchTerm = [[NSString stringWithFormat:@"%@ (%%", packageIdentifier] UTF8String];
    const char *fourthSearchTerm = [[NSString stringWithFormat:@"%@, %%", packageIdentifier] UTF8String];
    const char *fifthSearchTerm = [[NSString stringWithFormat:@"%%, %@", packageIdentifier] UTF8String];
    const char *sixthSearchTerm = [[NSString stringWithFormat:@"%%| %@", packageIdentifier] UTF8String];
    const char *seventhSearchTerm = [[NSString stringWithFormat:@"%%, %@ |%%", packageIdentifier] UTF8String];
    const char *eighthSearchTerm = [[NSString stringWithFormat:@"%@ |%%", packageIdentifier] UTF8String];
    
    const char *query = "SELECT * FROM PACKAGES WHERE (DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS LIKE ? OR DEPENDS = ?) AND SOURCE = \'_var_lib_dpkg_status_\';";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, firstSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, secondSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, thirdSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 4, fourthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 5, fifthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 6, sixthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 7, seventhSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 8, eighthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 9, [packageIdentifier UTF8String], -1, SQLITE_TRANSIENT);
        
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char *dependsChars = (const char *)sqlite3_column_text(statement, ZBPackageColumnDepends);
            NSString *depends = dependsChars != 0 ? [NSString stringWithUTF8String:dependsChars] : NULL; //Depends shouldn't be NULL here but you know just in case because this can be weird
            NSArray *dependsOn = [depends componentsSeparatedByString:@", "];
            
            BOOL packageNeedsToBeRemoved = NO;
            for (NSString *dependsLine in dependsOn) {
                NSError *error = NULL;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b%@\\b", [package identifier]] options:NSRegularExpressionCaseInsensitive error:&error];
                if ([regex numberOfMatchesInString:dependsLine options:0 range:NSMakeRange(0, [dependsLine length])] && ![self willDependencyBeSatisfiedAfterQueueOperations:dependsLine]) { //Use regex to search with block words
                    packageNeedsToBeRemoved = YES;
                }
            }
            
            if (packageNeedsToBeRemoved) {
                ZBPackage *found = [[ZBPackage alloc] initFromSQLiteStatement:statement];
                if ([[ZBQueue sharedQueue] locate:found] == ZBQueueTypeClear) {
                    [found setRemovedBy:package];
                    
                    [packages addObject:found];
                }
            }
        }
    }
    sqlite3_finalize(statement);
    
    for (NSString *provided in [package provides]) { //If the package is removed and there is no other package that provides this dependency, we have to remove those as well
        if ([provided containsString:packageIdentifier]) continue;
        if (![[package identifier] isEqualToString:packageIdentifier] && [[package provides] containsObject:provided]) continue;
        if (![self willDependencyBeSatisfiedAfterQueueOperations:provided]) {
            [packages addObjectsFromArray:[self packagesThatDependOnPackageIdentifier:provided removedPackage:package]];
        }
    }
    
    return packages.count ? packages : nil;
}

- (NSArray <ZBPackage *> * _Nullable)packagesThatConflictWith:(ZBPackage *)package {
    NSMutableArray *packages = [NSMutableArray new];
    
    const char *firstSearchTerm = [[NSString stringWithFormat:@"%%, %@ (%%", [package identifier]] UTF8String];
    const char *secondSearchTerm = [[NSString stringWithFormat:@"%%, %@, %%", [package identifier]] UTF8String];
    const char *thirdSearchTerm = [[NSString stringWithFormat:@"%@ (%%", [package identifier]] UTF8String];
    const char *fourthSearchTerm = [[NSString stringWithFormat:@"%@, %%", [package identifier]] UTF8String];
    const char *fifthSearchTerm = [[NSString stringWithFormat:@"%%, %@", [package identifier]] UTF8String];
    const char *sixthSearchTerm = [[NSString stringWithFormat:@"%%| %@", [package identifier]] UTF8String];
    const char *seventhSearchTerm = [[NSString stringWithFormat:@"%%, %@ |%%", [package identifier]] UTF8String];
    const char *eighthSearchTerm = [[NSString stringWithFormat:@"%@ |%%", [package identifier]] UTF8String];
    
    const char *query = "SELECT * FROM PACKAGES WHERE (CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS LIKE ? OR CONFLICTS = ?) AND SOURCE = \'_var_lib_dpkg_status_\';";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, firstSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 2, secondSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 3, thirdSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 4, fourthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 5, fifthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 6, sixthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 7, seventhSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 8, eighthSearchTerm, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(statement, 9, [[package identifier] UTF8String], -1, SQLITE_TRANSIENT);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            ZBPackage *found = [[ZBPackage alloc] initFromSQLiteStatement:statement];
            [packages addObject:found];
        }
    }
    
    for (ZBPackage *conflictingPackage in [packages copy]) {
        for (NSString *conflict in [conflictingPackage conflicts]) {
            if (([conflict containsString:@"("] || [conflict containsString:@")"]) && [conflict containsString:[package identifier]]) {
                NSArray *versionComparison = [ZBDependencyResolver separateVersionComparison:conflict];
                if (![ZBDependencyResolver doesPackage:package satisfyComparison:versionComparison[1] ofVersion:versionComparison[2]]) {
                    [packages removeObject:conflictingPackage];
                }
            }
        }
    }
    
    sqlite3_finalize(statement);
    
    return packages.count ? packages : nil;
}

- (BOOL)willDependencyBeSatisfiedAfterQueueOperations:(NSString *_Nonnull)dependency {
    if ([dependency containsString:@"|"]) {
        NSArray *components = [dependency componentsSeparatedByString:@"|"];
        for (NSString *dependency in components) {
            if ([self willDependencyBeSatisfiedAfterQueueOperations:[dependency stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]) {
                return YES;
            }
        }
    }
    else {
        ZBQueue *queue = [ZBQueue sharedQueue];
        NSDictionary *addedPackages = [queue packagesQueuedForAddition]; //Packages that are being installed, upgraded, removed, downgraded, etc. (dependencies as well)
        NSArray *removedPackages = [queue packageIDsQueuedForRemoval]; //Just packageIDs that are queued for removal (conflicts as well)
        
        NSArray *versionComponents = [ZBDependencyResolver separateVersionComparison:dependency];
        NSString *packageIdentifier = versionComponents[0];
        BOOL needsVersionComparison = ![versionComponents[1] isEqualToString:@"<=>"] && ![versionComponents[2] isEqualToString:@"0:0"];
        
        NSString *excludeString = [self excludeStringFromArray:removedPackages];
        const char *firstSearchTerm = [[NSString stringWithFormat:@"%%, %@ (%%", packageIdentifier] UTF8String];
        const char *secondSearchTerm = [[NSString stringWithFormat:@"%%, %@, %%", packageIdentifier] UTF8String];
        const char *thirdSearchTerm = [[NSString stringWithFormat:@"%@ (%%", packageIdentifier] UTF8String];
        const char *fourthSearchTerm = [[NSString stringWithFormat:@"%@, %%", packageIdentifier] UTF8String];
        const char *fifthSearchTerm = [[NSString stringWithFormat:@"%%, %@", packageIdentifier] UTF8String];
        const char *sixthSearchTerm = [[NSString stringWithFormat:@"%%| %@", packageIdentifier] UTF8String];
        const char *seventhSearchTerm = [[NSString stringWithFormat:@"%%, %@ |%%", packageIdentifier] UTF8String];
        const char *eighthSearchTerm = [[NSString stringWithFormat:@"%@ |%%", packageIdentifier] UTF8String];
        
        NSString *query = [NSString stringWithFormat:@"SELECT VERSION FROM PACKAGES WHERE IDENTIFIER NOT IN %@ AND SOURCE = \'_var_lib_dpkg_status_\' AND (IDENTIFIER = ? OR (PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ? OR PROVIDES LIKE ?)) LIMIT 1;", excludeString];
        
        BOOL found = NO;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(database, [query UTF8String], -1, &statement, nil) == SQLITE_OK) {
            sqlite3_bind_text(statement, 1, [packageIdentifier UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 2, firstSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 3, secondSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 4, thirdSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 5, fourthSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 6, fifthSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 7, sixthSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 8, seventhSearchTerm, -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 9, eighthSearchTerm, -1, SQLITE_TRANSIENT);
            
            while (sqlite3_step(statement) == SQLITE_ROW) {
                if (needsVersionComparison) {
                    const char* foundVersion = (const char*)sqlite3_column_text(statement, 0);
                    
                    if (foundVersion != 0) {
                        if ([ZBDependencyResolver doesVersion:[NSString stringWithUTF8String:foundVersion] satisfyComparison:versionComponents[1] ofVersion:versionComponents[2]]) {
                            found = YES;
                            break;
                        }
                    }
                }
                else {
                    found = YES;
                    break;
                }
            }
            
            sqlite3_finalize(statement);
            
            if (!found) { //Search the array of packages that are queued for installation to see if one of them satisfies the dependency
                for (NSString *key in addedPackages) {
                    if ([key isEqualToString:packageIdentifier]) {
                        // TODO: Condition check here is useless
                        //                        if (needsVersionComparison && [ZBDependencyResolver doesVersion:[package objectForKey:@"version"] satisfyComparison:versionComponents[1] ofVersion:versionComponents[2]]) {
                        //                            return YES;
                        //                        }
                        return YES;
                    }
                }
                return NO;
            }
        }
        
        return found;
    }
    
    return NO;
}

#pragma mark - Helpers

- (NSString * _Nullable)excludeStringFromArray:(NSArray *)array {
    if ([array count]) {
        NSMutableString *result = [@"(" mutableCopy];
        [result appendString:[NSString stringWithFormat:@"\'%@\'", array[0]]];
        for (int i = 1; i < array.count; ++i) {
            [result appendFormat:@", \'%@\'", array[i]];
        }
        [result appendString:@")"];
        
        return result;
    }
    return NULL;
}

@end
