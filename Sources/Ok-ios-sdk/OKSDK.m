#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#import <WebKit/WebKit.h>
#import "OKSDK.h"

NSString *const OK_SDK_VERSION = @"2.0.14";
NSTimeInterval const OK_REQUEST_TIMEOUT = 180.0;
NSInteger const OK_MAX_CONCURRENT_REQUESTS = 3;
NSString *const OK_OAUTH_URL = @"https://connect.ok.ru/oauth/authorize";
NSString *const OK_API_URL = @"https://api.ok.ru/fb.do?";
NSString *const OK_USER_DEFS_ACCESS_TOKEN = @"ok_access_token";
NSString *const OK_USER_DEFS_SECRET_KEY = @"ok_secret_key";
NSString *const OK_API_ERROR_CODE_DOMAIN = @"ru.ok.api";
NSString *const OK_SDK_ERROR_CODE_DOMAIN = @"ru.ok.sdk";

typedef void (^OKCompletitionHander)(id data, NSError *error);
typedef void (^OKResultBlock)(id data);
typedef void (^OKErrorBlock)(NSError *error);

@implementation OKSDKInitSettings
@end

#pragma mark - Web Controller

@interface OKWebAuthController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSURL *authURL;
@property (nonatomic, copy) OKErrorBlock errorBlock;
@property (nonatomic, copy) void (^onComplete)(NSURL *url);
@end

@implementation OKWebAuthController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    self.title = @"Вход в ОК";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self
                             action:@selector(cancelPressed)];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    [self.webView loadRequest:[NSURLRequest requestWithURL:self.authURL]];
}

- (void)cancelPressed {
    if (self.errorBlock) {
        NSError *error = [NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN
                                             code:8
                                         userInfo:@{NSLocalizedDescriptionKey: @"Пользователь отменил вход"}];
        self.errorBlock(error);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    if ([url.absoluteString containsString:@"access_token="]) {
        if (self.onComplete) self.onComplete(url);
        [self dismissViewControllerAnimated:YES completion:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (self.errorBlock) self.errorBlock(error);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Connection

@interface OKConnection : NSObject
@property (nonatomic, strong) OKSDKInitSettings *settings;
@property (nonatomic, copy) NSString *oauthRedirectUri;
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *accessTokenSecretKey;
@property (nonatomic, strong) NSMutableDictionary *completitionHandlers;
@end

@implementation OKConnection

- (instancetype)initWithSettings:(OKSDKInitSettings *)settings {
    if (self = [super init]) {
        _settings = settings;
        NSString *scheme = [NSString stringWithFormat:@"ok%@", settings.appId];
        _oauthRedirectUri = [NSString stringWithFormat:@"%@://authorize", scheme];
        _completitionHandlers = [NSMutableDictionary dictionary];

        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        _accessToken = [ud objectForKey:OK_USER_DEFS_ACCESS_TOKEN];
        _accessTokenSecretKey = [ud objectForKey:OK_USER_DEFS_SECRET_KEY];
    }
    return self;
}

- (void)authorizeWithPermissions:(NSArray *)permissions success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if (self.accessToken && self.accessTokenSecretKey) {
        return successBlock(@[self.accessToken, self.accessTokenSecretKey]);
    }

    NSString *scope = [[permissions componentsJoinedByString:@";"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *redirect = [self.oauthRedirectUri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *urlStr = [NSString stringWithFormat:@"%@?response_type=token&client_id=%@&redirect_uri=%@&layout=a&scope=%@",
                        OK_OAUTH_URL, self.settings.appId, redirect, scope];
    NSURL *url = [NSURL URLWithString:urlStr];

    UIViewController *host = self.settings.controllerHandler();
    OKWebAuthController *vc = [OKWebAuthController new];
    vc.authURL = url;
    vc.errorBlock = errorBlock;
    __weak typeof(self) weakSelf = self;
    vc.onComplete = ^(NSURL *url) {
        [weakSelf handleOAuthCallback:url success:successBlock error:errorBlock];
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)handleOAuthCallback:(NSURL *)url success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    NSString *fragment = url.fragment ?: url.query;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSString *pair in [fragment componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            params[kv[0]] = kv[1];
        }
    }

    if (params[@"access_token"]) {
        self.accessToken = params[@"access_token"];
        self.accessTokenSecretKey = params[@"session_secret_key"];
        NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
        [ud setObject:self.accessToken forKey:OK_USER_DEFS_ACCESS_TOKEN];
        [ud setObject:self.accessTokenSecretKey forKey:OK_USER_DEFS_SECRET_KEY];
        [ud synchronize];
        successBlock(@[self.accessToken, self.accessTokenSecretKey]);
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:5 userInfo:@{NSLocalizedDescriptionKey: @"OAuth error"}]);
    }
}

- (void)clearAuth {
    self.accessToken = nil;
    self.accessTokenSecretKey = nil;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud removeObjectForKey:OK_USER_DEFS_ACCESS_TOKEN];
    [ud removeObjectForKey:OK_USER_DEFS_SECRET_KEY];

    if (@available(iOS 9.0, *)) {
        NSSet *types = [NSSet setWithObject:WKWebsiteDataTypeCookies];
        [[WKWebsiteDataStore defaultDataStore] fetchDataRecordsOfTypes:types completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
            for (WKWebsiteDataRecord *record in records) {
                if ([record.displayName containsString:@"ok.ru"] || [record.displayName containsString:@"odnoklassniki.ru"]) {
                    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types forDataRecords:@[record] completionHandler:^{}];
                }
            }
        }];
    }
}

@end

#pragma mark - OKSDK

@implementation OKSDK

static OKConnection *connection;

+ (void)initWithSettings:(OKSDKInitSettings *)settings {
    connection = [[OKConnection alloc] initWithSettings:settings];
}

+ (void)authorizeWithPermissions:(NSArray *)permissions success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    [connection authorizeWithPermissions:permissions success:successBlock error:errorBlock];
}

+ (void)clearAuth {
    [connection clearAuth];
}

+ (NSString *)currentAccessToken {
    return connection.accessToken;
}

+ (NSString *)currentAccessTokenSecretKey {
    return connection.accessTokenSecretKey;
}

@end
