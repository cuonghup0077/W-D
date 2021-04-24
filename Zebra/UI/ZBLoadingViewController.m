//
//  ZBLoadingViewController.m
//  Zebra
//
//  Created by Wilson Styres on 3/25/21.
//  Copyright © 2021 Wilson Styres. All rights reserved.
//

#import "ZBLoadingViewController.h"

#import <Extensions/UIColor+GlobalColors.h>

@interface ZBLoadingViewController ()

@end

@implementation ZBLoadingViewController

- (void)loadView {
    [super loadView];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    
    [self.view addSubview:spinner];
    
    [spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor].active = YES;
    
    UILabel *loadingLabel = [[UILabel alloc] init];
    loadingLabel.text = @"LOADING";
    loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    loadingLabel.textColor = [UIColor secondaryTextColor];
    loadingLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightThin];
    
    [self.view addSubview:loadingLabel];
    
    [loadingLabel.topAnchor constraintEqualToAnchor:spinner.bottomAnchor constant:6].active = YES;
    [loadingLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    
    UITabBar *dummyBar = [[UITabBar alloc] init];
    dummyBar.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addSubview:dummyBar];
    
    [dummyBar.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
    [dummyBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [dummyBar.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
}

@end