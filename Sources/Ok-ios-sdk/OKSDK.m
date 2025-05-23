// OKWebAuthController.h/.m встроено прямо в OKSDK.m

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
NSString *const OK_WIDGET_URL = @"https://connect.ok.ru/dk?st.cmd=";
NSString *const OK_API_URL = @"https://api.ok.ru/fb.do?";
NSString *const OK_OAUTH_APP_URL = @"okauth://authorize";
NSString *const OK_USER_DEFS_ACCESS_TOKEN = @"ok_access_token";
NSString *const OK_USER_DEFS_SECRET_KEY = @"ok_secret_key";
NSString *const OK_SDK_NOT_INIT_COMMON_ERROR = @"OKSDK not initialized you should call initWithSettings first";
NSString *const OK_API_ERROR_CODE_DOMAIN = @"ru.ok.api";
NSString *const OK_SDK_ERROR_CODE_DOMAIN = @"ru.ok.sdk";

typedef void (^OKCompletitionHander)(id data, NSError *error);

typedef void (^OKResultBlock)(id data);
typedef void (^OKErrorBlock)(NSError *error);

@interface OKSDKInitSettings : NSObject
@property (nonatomic, strong) NSString *appId;
@property (nonatomic, strong) NSString *appKey;
@property (nonatomic, strong) UIViewController* (^controllerHandler)(void);
@end

@implementation OKSDKInitSettings
@end

@interface OKWebAuthController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSURL *authURL;
@property (nonatomic, copy) OKErrorBlock errorBlock;
@property (nonatomic, copy) void (^onComplete)(NSURL *url);
@end

@implementation OKWebAuthController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds];
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.authURL]];
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

@interface OKConnection : NSObject
@property (nonatomic, strong) OKSDKInitSettings *settings;
@property (nonatomic, copy) NSString *oauthRedirectScheme;
@property (nonatomic, copy) NSString *oauthRedirectUri;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, weak) UIViewController *authVC;
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *accessTokenSecretKey;
@property (nonatomic, strong) NSString *sdkToken;
@property (nonatomic, strong) NSMutableDictionary *completitionHandlers;
@end

@implementation OKConnection

- (instancetype)initWithSettings:(OKSDKInitSettings *)settings {
    if (self = [super init]) {
        _settings = settings;
        _queue = [[NSOperationQueue alloc] init];
        _queue.name = @"OK-API-Requests";
        _queue.maxConcurrentOperationCount = OK_MAX_CONCURRENT_REQUESTS;
        _oauthRedirectScheme = [NSString stringWithFormat:@"ok%@", _settings.appId];
        _oauthRedirectUri = [NSString stringWithFormat:@"%@://authorize", _oauthRedirectScheme];
        _completitionHandlers = [NSMutableDictionary new];
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        _accessToken = [userDefaults objectForKey:OK_USER_DEFS_ACCESS_TOKEN];
        _accessTokenSecretKey = [userDefaults objectForKey:OK_USER_DEFS_SECRET_KEY];
    }
    return self;
}

- (void)openInWebView:(NSURL *)url success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = self.settings.controllerHandler();
        OKWebAuthController *vc = [OKWebAuthController new];
        vc.authURL = url;
        vc.errorBlock = errorBlock;
        __weak typeof(self) weakSelf = self;
        vc.onComplete = ^(NSURL *url) {
            [weakSelf openUrl:url];
        };
        [host presentViewController:vc animated:YES completion:nil];
        self.authVC = vc;
    });
}

- (BOOL)openUrl:(NSURL *)url {
    NSString *key = [[url absoluteString] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#?"]][0];
    OKCompletitionHander handler = self.completitionHandlers[key];
    NSDictionary *params = [self extractParams:url];
    if (handler) {
        [self.completitionHandlers removeObjectForKey:key];
        handler(params, nil);
        return YES;
    } else if ([key isEqualToString:self.oauthRedirectUri]) {
        [self saveTokens:params];
        return YES;
    }
    return NO;
}

- (NSDictionary *)extractParams:(NSURL *)url {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *components = [[url fragment] ?: [url query] componentsSeparatedByString:@"&"];
    for (NSString *pair in components) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) result[kv[0]] = kv[1];
    }
    return result;
}

- (void)authorizeWithPermissions:(NSArray *)permissions success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if (self.accessToken && self.accessTokenSecretKey) return successBlock(@[self.accessToken, self.accessTokenSecretKey]);

    if (![NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleURLTypes"]) {
        return errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:2 userInfo:nil]);
    }

    NSString *queryString = [NSString stringWithFormat:@"response_type=token&client_id=%@&redirect_uri=%@&layout=a&scope=%@",
                             self.settings.appId,
                             [self.oauthRedirectUri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet],
                             [[permissions componentsJoinedByString:@";"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];

    NSString *urlStr = [NSString stringWithFormat:@"%@?%@", OK_OAUTH_URL, queryString];
    NSURL *url = [NSURL URLWithString:urlStr];

    __weak typeof(self) weakSelf = self;
    self.completitionHandlers[self.oauthRedirectUri] = ^(NSDictionary *data, NSError *error) {
        if (error) errorBlock(error);
        else {
            [weakSelf saveTokens:data];
            if (weakSelf.accessToken && weakSelf.accessTokenSecretKey)
                successBlock(@[weakSelf.accessToken, weakSelf.accessTokenSecretKey]);
            else
                errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:7 userInfo:nil]);
        }
    };

    [self openInWebView:url success:successBlock error:errorBlock];
}

- (void)saveTokens:(NSDictionary *)data {
    self.accessToken = data[@"access_token"];
    self.accessTokenSecretKey = data[@"session_secret_key"];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:self.accessToken forKey:OK_USER_DEFS_ACCESS_TOKEN];
    [userDefaults setObject:self.accessTokenSecretKey forKey:OK_USER_DEFS_SECRET_KEY];
    [userDefaults synchronize];
}

- (void)clearAuth {
    self.accessToken = nil;
    self.accessTokenSecretKey = nil;
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults removeObjectForKey:OK_USER_DEFS_ACCESS_TOKEN];
    [userDefaults removeObjectForKey:OK_USER_DEFS_SECRET_KEY];

    if (@available(iOS 9.0, *)) {
        NSSet *types = [NSSet setWithObject:WKWebsiteDataTypeCookies];
        WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
        [dataStore fetchDataRecordsOfTypes:types completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
            for (WKWebsiteDataRecord *record in records) {
                if ([record.displayName containsString:@"ok.ru"] || [record.displayName containsString:@"odnoklassniki.ru"]) {
                    [dataStore removeDataOfTypes:types forDataRecords:@[record] completionHandler:^{}];
                }
            }
        }];
    }
}
@end

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
