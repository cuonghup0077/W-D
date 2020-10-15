//
//  ZBSource.h
//  Zebra
//
//  Created by Wilson Styres on 11/30/18.
//  Copyright © 2018 Wilson Styres. All rights reserved.
//

@class UIImage;
@class ZBUserInfo;
@class ZBSourceInfo;

#import "ZBBaseSource.h"

@import Foundation;
@import SQLite3;

NS_ASSUME_NONNULL_BEGIN

@interface ZBSource : ZBBaseSource
@property (nonatomic) NSString * _Nullable sourceDescription;
@property (nonatomic) NSString *origin;
@property (nonatomic) NSString *version;
@property (nonatomic) NSString *suite;
@property (nonatomic) NSString *codename;
@property (nonatomic) NSArray <NSString *> *architectures;

@property (nonatomic) BOOL supportsFeaturedPackages;
@property (nonatomic) BOOL checkedSupportFeaturedPackages;

@property (readonly, nonatomic) NSInteger pinPriority;

+ (ZBSource *)localSource;
+ (ZBSource * _Nullable)sourceFromBaseURL:(NSString *)baseURL;
+ (ZBSource * _Nullable)sourceFromBaseFilename:(NSString *)baseFilename;
+ (BOOL)exists:(NSString *)urlString;
+ (UIImage *)imageForSection:(NSString *)section;
- (id)initWithSQLiteStatement:(sqlite3_stmt *)statement;

#pragma mark - Modern Payment API

- (NSString *)paymentSecret:(NSError **)error;
- (void)authenticate:(void (^)(BOOL success, BOOL notify, NSError *_Nullable error))completion;
- (void)signOut;
- (BOOL)isSignedIn;
- (NSURL *)paymentVendorURL;
- (BOOL)suppotsPaymentAPI;
- (void)getUserInfo:(void (^)(ZBUserInfo *info, NSError *error))completion;
- (void)getSourceInfo:(void (^)(ZBSourceInfo *info, NSError *error))completion;

@end

NS_ASSUME_NONNULL_END