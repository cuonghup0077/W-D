//
//  ZBPackageDepictionViewController.m
//  Zebra
//
//  Created by Wilson Styres on 1/23/19.
//  Copyright © 2019 Wilson Styres. All rights reserved.
//

#import "ZBLog.h"
#import "ZBAppDelegate.h"
#import "ZBDevice.h"
#import "ZBSettings.h"
#import "ZBPackageDepictionViewController.h"
#import "UICKeyChainStore.h"
#import "ZBQueue.h"
#import "ZBDatabaseManager.h"
#import <SafariServices/SafariServices.h>
#import "ZBPackage.h"
#import "ZBPackageActions.h"
#import "ZBSource.h"
#import "ZBTabBarController.h"
#import "UIColor+GlobalColors.h"
#import "ZBPurchaseInfo.h"
#import "ZBPackageActionType.h"
#import "UIBarButtonItem+blocks.h"
#import <objc/runtime.h>

@import SDWebImage;

typedef NS_ENUM(NSUInteger, ZBPackageInfoOrder) {
    ZBPackageInfoID = 0,
    ZBPackageInfoAuthor,
    ZBPackageInfoVersion,
    ZBPackageInfoSize,
    ZBPackageInfoSource,
    ZBPackageInfoWishList,
    ZBPackageInfoMoreBy,
    ZBPackageInfoInstalledFiles
};

@interface ZBPackageDepictionViewController () {
    NSMutableDictionary<NSNumber *, NSString *> *infos;
    UIProgressView *progressView;
    WKWebView *webView;
    BOOL navButtonsBeingConfigured;
    CGFloat webViewSize;
}
@end

@implementation ZBPackageDepictionViewController

@synthesize delegate;
@synthesize previewingGestureRecognizerForFailureRelationship;
@synthesize sourceRect;
@synthesize sourceView;
@synthesize package;

- (id)initWithPackage:(ZBPackage *)package {
    if (!package) return NULL;
    
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle: nil];
    self = [storyboard instantiateViewControllerWithIdentifier:@"packageDepictionVC"];
    
    if (self) {
        self.package = package;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (package == NULL) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Package Not Available", @"") message:NSLocalizedString(@"The package you request is no longer available. It might have been removed from your sources or the package ID requested was incorrect.", @"") preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *action = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:action];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
    
    UIActivityIndicatorViewStyle style = [ZBSettings interfaceStyle] >= ZBInterfaceStyleDark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
    UIActivityIndicatorView *uiBusy = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
    [uiBusy startAnimating];
    
    UIBarButtonItem *busyButton = [[UIBarButtonItem alloc] initWithCustomView:uiBusy];
    self.navigationItem.rightBarButtonItem = busyButton;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDepiction) name:@"darkMode" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(configureNavButton) name:@"ZBUpdateNavigationButtons" object:nil];

    self.navigationItem.title = package.name;
    if (@available(iOS 11.0, *)) {
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    else {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    
    self.view.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    
    self.packageIcon.layer.cornerRadius = 20;
    self.packageIcon.layer.masksToBounds = YES;
    infos = [NSMutableDictionary new];
    [self setPackage];
    
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    
    configuration.allowsInlineMediaPlayback = YES;
    if (@available(iOS 10.0, *)) {
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAudio;
    }
    
    switch ([ZBSettings interfaceStyle]) {
        case ZBInterfaceStyleLight:
            configuration.applicationNameForUserAgent = [NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Light", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]];
            break;
        case ZBInterfaceStyleDark:
            configuration.applicationNameForUserAgent = [NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Dark", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]];
            break;
        case ZBInterfaceStylePureBlack:
            configuration.applicationNameForUserAgent = [NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Pure-Black", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]];
            break;
    }
    
    webViewSize = 0;
    webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 300) configuration:configuration];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.scrollView.scrollEnabled = NO;
    webView.opaque = NO;
    webView.backgroundColor = [UIColor tableViewBackgroundColor];
    
    progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0,0,0,0)];
    progressView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.tableView.tableHeaderView addSubview:progressView];
    [self.tableView setTableFooterView:webView];
    
    // Progress View Layout
    [progressView.trailingAnchor constraintEqualToAnchor:self.tableView.tableHeaderView.trailingAnchor].active = YES;
    [progressView.leadingAnchor constraintEqualToAnchor:self.tableView.tableHeaderView.leadingAnchor].active = YES;
    [progressView.topAnchor constraintEqualToAnchor:self.tableView.tableHeaderView.topAnchor].active = YES;
    
    progressView.tintColor = [UIColor accentColor] ?: [UIColor systemBlueColor];
    
    webView.navigationDelegate = self;
    
    if (package.depictionURL && ([package.depictionURL.scheme isEqualToString:@"http"] || [package.depictionURL.scheme isEqualToString:@"https"])) {
        [self prepDepictionLoading:[package depictionURL]];
    } else {
        [self prepDepictionLoading:[[NSBundle mainBundle] URLForResource:@"package_depiction" withExtension:@"html"]];
    }
    [webView addObserver:self forKeyPath:NSStringFromSelector(@selector(estimatedProgress)) options:NSKeyValueObservingOptionNew context:NULL];
    [webView.scrollView addObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize)) options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.tableView.separatorColor = [UIColor cellSeparatorColor];
    self.tableView.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    self.tableView.tableHeaderView.backgroundColor = [UIColor groupedTableViewBackgroundColor];
    [self configureNavButton];
}

- (BOOL)presented {
    return [self.navigationController.viewControllers[0] isEqual:self];
}

- (void)prepDepictionLoading:(NSURL *)url {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSString *version = [[UIDevice currentDevice] systemVersion];
    NSString *machineIdentifier = [ZBDevice machineID];

    //Set theme settings and user agent
    switch ([ZBSettings interfaceStyle]) {
        case ZBInterfaceStyleLight: {
            [request setValue:@"Light" forHTTPHeaderField:@"Theme"];
            [request setValue:[NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Light", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]] forHTTPHeaderField:@"User-Agent"];
            break;
        }
        case ZBInterfaceStyleDark: {
            [request setValue:@"Dark" forHTTPHeaderField:@"Theme"];
            [request setValue:[NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Dark", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]] forHTTPHeaderField:@"User-Agent"];
            break;
        }
        case ZBInterfaceStylePureBlack: {
            [request setValue:@"Pure-Black" forHTTPHeaderField:@"Theme"];
            [request setValue:[NSString stringWithFormat:@"Cydia/1.1.32 Zebra/%@ (%@; iOS/%@) Pure-Black", PACKAGE_VERSION, [ZBDevice deviceType], [[UIDevice currentDevice] systemVersion]] forHTTPHeaderField:@"User-Agent"];
            break;
        }
    }
    
    [request setValue:version forHTTPHeaderField:@"X-Firmware"];
    [request setValue:machineIdentifier forHTTPHeaderField:@"X-Machine"];
    [request setValue:@"API" forHTTPHeaderField:@"Payment-Provider"];
    [request setValue:[UIColor hexStringFromColor:[UIColor accentColor]] forHTTPHeaderField:@"Tint-Color"];
    [request setValue:[[NSLocale preferredLanguages] firstObject] forHTTPHeaderField:@"Accept-Language"];
    
    webView.scrollView.backgroundColor = [UIColor tableViewBackgroundColor];
    [webView loadRequest:request];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(estimatedProgress))] && object == webView) {
        progressView.alpha = 1.0;
        
        if (webView.estimatedProgress >= 1.0) {
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                [self->progressView setProgress:self->webView.estimatedProgress animated:YES];
            } completion:nil];

            [UIView animateWithDuration:0.3 delay:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
                [self->progressView setAlpha:0.0];
            } completion:^(BOOL finished) {
                [self->progressView setProgress:0.0 animated:NO];
            }];
        } else {
            [progressView setProgress:webView.estimatedProgress animated:YES];
        }
    } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
        CGFloat newSize = [(UIScrollView *)object contentSize].height;
        if (newSize != webViewSize) {
            webViewSize = newSize;
            [self layoutDepictionWebView:webView];
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)goodbye {
    if ([self presentingViewController]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)escape:(NSMutableString *)s {
    [s replaceOccurrencesOfString:@"\r" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\n" withString:@"<br>" options:NSLiteralSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\'" withString:@"\\\'" options:NSLiteralSearch range:NSMakeRange(0, s.length)];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (package == nil)
        return;
    
    [self performSelector:@selector(layoutDepictionWebView:) withObject:webView afterDelay:1.0];
    
    NSString *js = @"var meta = document.createElement('meta'); meta.name = 'viewport'; meta.content = 'initial-scale=1, maximum-scale=1, user-scalable=0'; var head = document.getElementsByTagName('head')[0]; head.appendChild(meta);";
    [webView evaluateJavaScript:js completionHandler:nil];
    
    if ([webView.URL.absoluteString isEqualToString:[[NSBundle mainBundle] URLForResource:@"package_depiction" withExtension:@"html"].absoluteString]) {
        if ([ZBSettings interfaceStyle] >= ZBInterfaceStyleDark) {
            NSString *path = [[NSBundle mainBundle] pathForResource:[ZBSettings interfaceStyle] == ZBInterfaceStylePureBlack ? @"ios7oled" : @"ios7dark" ofType:@"css"];

            NSString *cssData = [NSString stringWithContentsOfFile:path encoding:NSASCIIStringEncoding error:nil];
            cssData = [cssData stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            cssData = [cssData stringByReplacingOccurrencesOfString:@"\n" withString:@""];
            NSString *jsString = [NSString stringWithFormat:@"var style = document.createElement('style'); \
                                  style.innerHTML = '%@'; \
                                  document.head.appendChild(style)",
                                  cssData];
            [webView evaluateJavaScript:jsString
                      completionHandler:^(id _Nullable result, NSError *_Nullable error) {
                          if (error) {
                              ZBLog(@"[Zebra] Error setting web dark mode: %@", error.localizedDescription);
                          }
                      }];
        }
        
        if (![[package shortDescription] isEqualToString:@""] && [package shortDescription] != NULL) {
            [webView evaluateJavaScript:@"var element = document.getElementById('depiction-src').outerHTML = '';" completionHandler:nil];
            
            NSString *originalDescription = [package longDescription];
            NSMutableString *description = [NSMutableString stringWithCapacity:originalDescription.length];
            [description appendString:originalDescription];
            
            [self escape:description];
            
            NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
            NSArray *matches = [linkDetector matchesInString:description options:0 range:NSMakeRange(0, description.length)];
            NSUInteger rangeShift = 0;
            for (NSTextCheckingResult *result in matches) {
                NSString *urlString = result.URL.absoluteString;
                NSUInteger before = result.range.length;
                NSString *anchor = [NSString stringWithFormat:@"<a href=\\\"%@\\\">%@</a>", urlString, urlString];
                [description replaceCharactersInRange:NSMakeRange(result.range.location + rangeShift, result.range.length) withString:anchor];
                rangeShift += anchor.length - before;
            }
            
            [webView evaluateJavaScript:[NSString stringWithFormat:@"document.getElementById('desc').innerHTML = \"%@\";", description] completionHandler:nil];
        } else {
            [webView evaluateJavaScript:@"var element = document.getElementById('desc-holder').outerHTML = '';" completionHandler:nil];
        }
    }
}

- (void)layoutDepictionWebView:(WKWebView *)webView {
    if (webView) {
        [webView evaluateJavaScript:@"document.readyState" completionHandler:^(id _Nullable completed, NSError * _Nullable error) {
            if (!error) {
                if ([completed isEqualToString:@"complete"]) {
                    //body.scrollHeight, body.offsetHeight, html.clientHeight, html.scrollHeight, html.offsetHeight
                    NSString *question = @"var body = document.body, html = document.documentElement; var height = Math.max(body.scrollHeight, body.offsetHeight, html.clientHeight, html.offsetHeight); height";
                    [webView evaluateJavaScript:question completionHandler:^(id _Nullable height, NSError * _Nullable error) {
                        [self layoutDepictionWebView:webView height:[height floatValue]];
                    }];
                }
            }
        }];
    }
}

- (void)layoutDepictionWebView:(WKWebView *)webView height:(CGFloat)height {
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView setFrame:CGRectMake(webView.frame.origin.x, webView.frame.origin.y, webView.frame.size.width, height)];
        [self.tableView beginUpdates];
        [self.tableView setTableFooterView:webView];
        [self.tableView endUpdates];
    });
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURLRequest *request = [navigationAction request];
    NSURL *url = [request URL];
    
    WKNavigationType type = navigationAction.navigationType;
    
    if ([navigationAction.request.URL isEqual:[[NSBundle mainBundle] URLForResource:@"package_depiction" withExtension:@"html"]] || (type == -1 && [navigationAction.request.URL isEqual:[package depictionURL]])) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else if (![navigationAction.request.URL isEqual:[NSURL URLWithString:@"about:blank"]]) {
        if (type != -1 && ([[url scheme] isEqualToString:@"http"] || [[url scheme] isEqualToString:@"https"])) {
            [ZBDevice openURL:url delegate:self];
            decisionHandler(WKNavigationActionPolicyCancel);
        } else if ([[url scheme] isEqualToString:@"mailto"]) {
            [[UIApplication sharedApplication] openURL:url];
            decisionHandler(WKNavigationActionPolicyCancel);
        } else {
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    } else {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error{
    [self prepDepictionLoading:[[NSBundle mainBundle] URLForResource:@"package_depiction" withExtension:@"html"]];
}

- (void)configureNavButton {
    if (navButtonsBeingConfigured) return;
    
    navButtonsBeingConfigured = YES;
    
    if ([self presented]) {
        UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Close", @"") style:UIBarButtonItemStylePlain target:self action:@selector(goodbye)];
        self.navigationItem.leftBarButtonItem = closeButton;
    }
    
    [ZBPackageActions barButtonItemForPackage:package completion:^(UIBarButtonItem *barButton) {
        self->navButtonsBeingConfigured = NO;
        
        if ([self presented]) {
            UIBarButtonItemActionHandler originalHandler = objc_getAssociatedObject(barButton, "actionHandler");
            UIBarButtonItemActionHandler newHandler = ^{
                originalHandler();
                [self goodbye];
            };
            
            [barButton setActionHandler:newHandler];
        }
        self.navigationItem.rightBarButtonItem = barButton;
    }];
}

- (void)dealloc {
    [webView removeObserver:self forKeyPath:NSStringFromSelector(@selector(estimatedProgress)) context:nil];
    [webView.scrollView removeObserver:self forKeyPath:NSStringFromSelector(@selector(contentSize)) context:nil];
}

// 3D Touch Actions

- (NSArray *)previewActionItems {
    return [ZBPackageActions previewActionsForPackage:package inTableView:_parent.tableView];
}

// Haptic Touch Actions

- (NSArray *)contextMenuActionItemsInTableView:(UITableView *_Nullable)tableView API_AVAILABLE(ios(13.0)) {
    return [ZBPackageActions menuElementsForPackage:package inTableView:tableView];
}

- (void)safariViewController:(SFSafariViewController *)controller didCompleteInitialLoad:(BOOL)didLoadSuccessfully {
    // Load finished
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    // Done button pressed
}

- (void)reloadDepiction {
    UIColor *tableViewBackgroundColor = [UIColor groupedTableViewBackgroundColor];
    [self prepDepictionLoading:webView.URL];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
    self.navigationController.navigationBar.barTintColor = tableViewBackgroundColor;
    self.tableView.backgroundColor = tableViewBackgroundColor;
    self.tableView.tableHeaderView.backgroundColor = tableViewBackgroundColor;
    self.tableView.tableFooterView.backgroundColor = tableViewBackgroundColor;
    self.packageName.textColor = [UIColor primaryTextColor];
    webView.backgroundColor = tableViewBackgroundColor;
}

- (NSArray *)packageInfoOrder {
    return NULL;
}

#pragma mark TableView

- (void)readIcon:(ZBPackage *)package {
    self.packageName.text = package.name;
    self.packageName.textColor = [UIColor primaryTextColor];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [package setIconImageForImageView:self.packageIcon];
    });
}

- (void)readPackageID:(ZBPackage *)package {
    if (package.identifier) {
        infos[@(ZBPackageInfoID)] = package.identifier;
    } else {
        [infos removeObjectForKey:@(ZBPackageInfoID)];
    }
}

- (void)setMoreByText:(ZBPackage *)package {
    if (package.authorName) {
        infos[@(ZBPackageInfoMoreBy)] = NSLocalizedString(@"More by this Developer", @"");
    } else {
        [infos removeObjectForKey:@(ZBPackageInfoMoreBy)];
    }
}

- (void)readVersion:(ZBPackage *)package {
    if (![package isInstalled:NO] || [package installedVersion] == nil) {
        infos[@(ZBPackageInfoVersion)] = package.version;
    } else {
        infos[@(ZBPackageInfoVersion)] = [NSString stringWithFormat:NSLocalizedString(@"%@ (Installed Version: %@)", @""), package.version, [package installedVersion]];
    }
}

- (void)readSize:(ZBPackage *)package {
    NSString *size = [package downloadSizeString];
    NSString *installedSize = [package installedSizeString];
    if (size && installedSize) {
        infos[@(ZBPackageInfoSize)] = [NSString stringWithFormat:NSLocalizedString(@"%@ (Installed Size: %@)", @""), size, installedSize];
    } else if (size) {
        infos[@(ZBPackageInfoSize)] = size;
    } else {
        infos[@(ZBPackageInfoSize)] = @"-";
    }
}

- (void)readRepo:(ZBPackage *)package {
    NSString *sourceName = [[package source] origin];
    if (sourceName) {
        infos[@(ZBPackageInfoSource)] = sourceName;
    } else {
        [infos removeObjectForKey:@(ZBPackageInfoSource)];
    }
}

- (void)readFiles:(ZBPackage *)package {
    if ([package isInstalled:NO] && [[package source] sourceID] != -2) {
        infos[@(ZBPackageInfoInstalledFiles)] = @"";
    } else {
        [infos removeObjectForKey:@(ZBPackageInfoInstalledFiles)];
    }
}

- (void)readAuthor:(ZBPackage *)package {
    NSString *authorName = [package authorName];
    if (authorName) {
        infos[@(ZBPackageInfoAuthor)] = authorName;
    } else {
        [infos removeObjectForKey:@(ZBPackageInfoAuthor)];
    }
}

- (void)setPackage {
    [self readIcon:package];
    [self readAuthor:package];
    [self readVersion:package];
    [self readSize:package];
    [self readRepo:package];
    [self readFiles:package];
    [self readPackageID:package];
    [self setMoreByText:package];
    infos[@(ZBPackageInfoWishList)] = @"";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)showSupportSelection:(UIView *)sender {
    if (self.package.supportURL && self.package.authorEmail) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Email Author", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *alertAction) {
            [self sendEmailToDeveloper];
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"View Support Website", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *alertAction) {
            [self openSupportURL];
        }]];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil]];
        alertController.popoverPresentationController.sourceView = sender;
        [self presentViewController:alertController animated:YES completion:nil];
    } else if (self.package.supportURL) {
        [self openSupportURL];
    } else if (self.package.authorEmail) {
        [self sendEmailToDeveloper];
    }
}

- (void)sendEmailToDeveloper {
    NSString *subject = [NSString stringWithFormat:@"Zebra: %@ (%@)", package.name, package.version];
    NSString *body = [NSString stringWithFormat:@"%@-%@: %@", [ZBDevice deviceModelID], [[UIDevice currentDevice] systemVersion], [ZBDevice UDID]];
    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController *mail = [[MFMailComposeViewController alloc] init];
        mail.mailComposeDelegate = self;
        [mail.navigationController.navigationBar setBarTintColor:[UIColor whiteColor]];
        [mail setSubject:subject];
        [mail setMessageBody:body isHTML:NO];
        [mail setToRecipients:@[self.package.authorEmail]];
        
        [self presentViewController:mail animated:YES completion:NULL];
    } else {
        NSURLComponents *url = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"mailto:%@", self.package.authorEmail]];
        url.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"subject" value:subject],
            [NSURLQueryItem queryItemWithName:@"body" value:body]
        ];
        if (@available(iOS 10.0, *)) {
            [[UIApplication sharedApplication] openURL:url.URL options:@{} completionHandler:nil];
        } else {
            [[UIApplication sharedApplication] openURL:url.URL];
        }
    }
}

- (void)openSupportURL {
    NSURL *supportURL = self.package.supportURL;
    if (!supportURL || (![supportURL.scheme isEqualToString:@"http"] && ![supportURL.scheme isEqualToString:@"https"])) {
        return;
    }
    [ZBDevice openURL:supportURL delegate:self];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
    // handle any error
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return infos[@(indexPath.row)] == nil ? 0 : 45;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *simpleTableIdentifier = @"PackageInfoTableViewCell";
    
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier];

    NSString *value = infos[@(indexPath.row)];
    
    if (cell == nil) {
        if (indexPath.row == ZBPackageInfoSize || indexPath.row == ZBPackageInfoVersion || indexPath.row == ZBPackageInfoSource) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:simpleTableIdentifier];
        } else {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:simpleTableIdentifier];
        }
    }

    cell.textLabel.text = nil;
    cell.textLabel.textColor = [UIColor primaryTextColor];

    cell.detailTextLabel.text = nil;
    cell.detailTextLabel.textColor = [UIColor secondaryTextColor];
    
    switch ((ZBPackageInfoOrder)indexPath.row) {
        case ZBPackageInfoID:
            cell.textLabel.text = value;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case ZBPackageInfoAuthor: {
            cell.textLabel.text = value;
            BOOL selectable = self.package.authorEmail || self.package.supportURL;
            cell.accessoryType = selectable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
            cell.selectionStyle = selectable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            break;
        }
        case ZBPackageInfoVersion:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Version", @"");
            cell.detailTextLabel.text = value;
            break;
        case ZBPackageInfoSize:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Size", @"");
            cell.detailTextLabel.text = value;
            break;
        case ZBPackageInfoSource:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = NSLocalizedString(@"Source", @"");
            cell.detailTextLabel.text = value;
            break;
        case ZBPackageInfoWishList: {
            BOOL inWishList = [[ZBSettings wishlist] containsObject:package.identifier];
            cell.textLabel.text = NSLocalizedString(inWishList ? @"Remove from Wish List" : @"Add to Wish List", @"");
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        } case ZBPackageInfoMoreBy:
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = value;
            break;
        case ZBPackageInfoInstalledFiles:
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = NSLocalizedString(@"Installed Files", @"");
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row == ZBPackageInfoID || (indexPath.row == ZBPackageInfoSource && package.source.sourceID > 0);
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(copy:));
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UIPasteboard *pasteBoard = [UIPasteboard generalPasteboard];
        NSString *content = nil;
        switch (indexPath.row) {
            case ZBPackageInfoID:
                content = cell.textLabel.text;
                break;
            case ZBPackageInfoSource:
                content = package.source.repositoryURI;
                break;
        }
        if (content) {
            [pasteBoard setString:content];
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    assert(section == 0);
    return infos.count;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBPackageInfoOrder row = indexPath.row;
    switch (row) {
        case ZBPackageInfoID:
            break;
        case ZBPackageInfoAuthor:
            [self showSupportSelection:[tableView cellForRowAtIndexPath:indexPath]];
            break;
        case ZBPackageInfoVersion:
        case ZBPackageInfoSize:
        case ZBPackageInfoSource:
            break;
        case ZBPackageInfoWishList: {
            NSMutableArray *wishList = [[ZBSettings wishlist] mutableCopy];
            BOOL inWishList = [wishList containsObject:package.identifier];
            if (inWishList) {
                [wishList removeObject:package.identifier];
            } else {
                [wishList addObject:package.identifier];
            }
            [ZBSettings setWishlist:wishList];
            
            [tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:ZBPackageInfoWishList inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            break;
        } case ZBPackageInfoMoreBy:
            [self performSegueWithIdentifier:@"seguePackageDepictionToMorePackages" sender:self.package.authorName];
            break;
        case ZBPackageInfoInstalledFiles: {
            UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
            ZBInstalledFilesTableViewController *filesController = [storyboard instantiateViewControllerWithIdentifier:@"installedFilesController"];
            filesController.navigationItem.title = NSLocalizedString(@"Installed Files", @"");
            [filesController setPackage:package];
            [[self navigationController] pushViewController:filesController animated:YES];
            break;
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"seguePackageDepictionToMorePackages"]) {
        ZBPackagesByAuthorTableViewController *destination = [segue destinationViewController];
        NSString *authorName = sender;
        destination.package = self.package;
        destination.developerName = authorName;
    }
}

// For old tweaks
- (void)modifyPackage {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Deprecated Method" message:@"A tweak is calling a deprecated method, please contact the author of this tweak to get an update so that it will not crash Zebra in the future." preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:ok];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

@end
