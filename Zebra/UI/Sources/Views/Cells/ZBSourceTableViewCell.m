//
//  ZBSourceTableViewCell.m
//  Zebra
//
//  Created by Andrew Abosh on 2019-05-02.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBSourceTableViewCell.h"
#import <Extensions/UIColor+GlobalColors.h>
#import <Model/ZBSource.h>
@import SDWebImage;

@interface ZBSourceTableViewCell () {
    UIActivityIndicatorView *spinner;
}
@end

@implementation ZBSourceTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.backgroundColor = [UIColor cellBackgroundColor];
    self.sourceLabel.textColor = [UIColor primaryTextColor];
    self.urlLabel.textColor = [UIColor secondaryTextColor];
    self.tintColor = [UIColor accentColor];
    
    self.iconImageView.layer.cornerRadius = self.iconImageView.frame.size.height * 0.2237;
    self.iconImageView.layer.borderWidth = 1;
    self.iconImageView.layer.borderColor = [[UIColor imageBorderColor] CGColor];
    self.iconImageView.layer.masksToBounds = YES;
    self.chevronView = (UIImageView *)(self.accessoryView);
    self.storeBadge.hidden = YES;
    
    spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:12];
    spinner.color = [UIColor grayColor];
}

- (void)setSource:(ZBBaseSource *)source {
    self.sourceLabel.text = source.label;
    self.urlLabel.text = source.repositoryURI;
    self.storeBadge.hidden = source.paymentEndpointURL == NULL;
    [self.iconImageView sd_setImageWithURL:source.iconURL placeholderImage:[UIImage imageNamed:@"Unknown"]];
    
    if (source.errors.count) {
        self.accessoryType = [source isKindOfClass:[ZBSource class]] ? UITableViewCellAccessoryDetailDisclosureButton : UITableViewCellAccessoryDetailButton;
        self.tintColor = [UIColor systemPinkColor];
    } else if (source.warnings.count) {
        self.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        self.tintColor = [UIColor systemYellowColor];
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    //FIXME: Fix pls
//    self.backgroundColor= [UIColor selectedCellBackgroundColor:highlighted];
}

- (void)clearAccessoryView {
    self.accessoryView = self.chevronView;
}

- (void)setSpinning:(BOOL)spinning {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (spinning) {
            self.accessoryView = self->spinner;
            [self->spinner startAnimating];
        } else {
            [self->spinner stopAnimating];
            self.accessoryView = self.chevronView;
        }
    });
}

- (void)setDisabled:(BOOL)disabled {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (disabled) {
            self.selectionStyle = UITableViewCellSelectionStyleNone;
            self.alpha = 0.5;
        } else {
            self.selectionStyle = UITableViewCellSelectionStyleDefault;
            self.alpha = 1.0;
        }
    });
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.iconImageView sd_cancelCurrentImageLoad];
    self.tintColor = [UIColor accentColor];
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    [self setDisabled:NO];
}

@end