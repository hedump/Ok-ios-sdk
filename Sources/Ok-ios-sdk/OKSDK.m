#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#import "OKSDK.h"
#ifdef __IPHONE_9_0
#import <SafariServices/SafariServices.h>
#endif

#define kIOS9x ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0f)  // TODO: заменить после перехода на SDK9

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
//export
NSString *const OK_API_ERROR_CODE_DOMAIN = @"ru.ok.api";
NSString *const OK_SDK_ERROR_CODE_DOMAIN = @"ru.ok.sdk";


typedef void (^OKCompletitionHander)(id data, NSError *error);
typedef void (^OKResultBlock)(id data);
typedef void (^OKErrorBlock)(NSError *error);

@implementation OKSDKInitSettings
@end

@implementation NSString (OKConnection)

- (NSString *)ok_md5 {
    const char *cStr = [self UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [output appendFormat:@"%02x", digest[i]];
    return  output;
}

- (NSString *)ok_encode {
    static NSMutableCharacterSet *characterSet;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        characterSet = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
        [characterSet removeCharactersInString:@"+=&%"];
    });
    return [self stringByAddingPercentEncodingWithAllowedCharacters:characterSet];
}

- (NSString *)ok_decode {
    return [self stringByRemovingPercentEncoding];
}

@end

@implementation NSURL (OKConnection)

- (NSMutableDictionary *)ok_params {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *pairs = [(self.fragment ?: self.query) componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            result[[(NSString *)kv[0] ok_decode]]=[kv[1] ok_decode];
        }
    }
    return result;
}

@end

@implementation NSBundle (CFBundleURLTypes)

+ (BOOL)ok_hasRegisteredURLScheme:(NSString *)URLScheme {
    static dispatch_once_t onceToken;
    static NSArray *URLTypes;
    dispatch_once(&onceToken, ^{
        URLTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
    });
    
    for (NSDictionary *URLType in URLTypes) {
        NSArray *URLSchemes = [URLType valueForKey:@"CFBundleURLSchemes"];
        if ([URLSchemes containsObject:URLScheme]) {
            return YES;
        }
    }
    return NO;
}

@end

@implementation NSDictionary (OKConnection)

- (NSError *)ok_error {
    if(self[@"error_code"]) {
        return [[NSError alloc] initWithDomain:OK_API_ERROR_CODE_DOMAIN code:[self[@"error_code"] intValue] userInfo:@{NSLocalizedDescriptionKey: self[@"error_msg"]}];
    }
    if(self[@"error"]) {
        return [[NSError alloc] initWithDomain:OK_API_ERROR_CODE_DOMAIN code:-1 userInfo:@{NSLocalizedDescriptionKey: self[@"error"]}];
    }
    return nil;
}

- (NSDictionary *)ok_union:(NSDictionary *)dict {
    NSMutableDictionary *dictionary =[[NSMutableDictionary alloc] initWithDictionary:self];
    [dictionary setValuesForKeysWithDictionary:dict];
    return dictionary;
}

- (NSString *)ok_queryStringWithSignature:(NSString *)secretKey sigName:(NSString *)sigName{
    NSMutableString *sigSource = [NSMutableString string];
    NSMutableString *queryString = [NSMutableString string];
    NSArray *sortedKeys = [[self allKeys] sortedArrayUsingSelector: @selector(compare:)];
    for (NSString *key in sortedKeys) {
        NSString *value = self[key];
        [sigSource appendString:[NSString stringWithFormat:@"%@=%@", key, value ]];
        [queryString appendString:[NSString stringWithFormat:@"%@=%@&", key, [value ok_encode]]];
    }
    [sigSource appendString:secretKey];
    [queryString appendString:[NSString stringWithFormat:@"%@=%@&", sigName, [sigSource ok_md5]]];
    return queryString;
}

- (NSString *)ok_queryString {
    NSMutableString *queryString = [NSMutableString string];
    for (NSString *key in self) [queryString appendString:[NSString stringWithFormat:@"%@=%@&", [key ok_encode], [self[key] ok_encode]]];
    return queryString;
}

- (NSString *)ok_json:(NSError *)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self options:0 error:&error ];
    return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
}

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

@interface OKConnection : NSObject

@property(nonatomic,strong) OKSDKInitSettings *settings;
@property(nonatomic,copy) NSString *oauthRedirectScheme;
@property(nonatomic,copy) NSString *oauthRedirectUri;

@property(nonatomic,strong) NSOperationQueue *queue;
@property(nonatomic,weak) UIViewController *safariVC;

@property(nonatomic,strong) NSString *accessToken;
@property(nonatomic,strong) NSString *accessTokenSecretKey;
@property(nonatomic,strong) NSString *sdkToken;

@property(nonatomic,strong) NSMutableDictionary *completitionHandlers;

@end

@implementation OKConnection

+ (NSError *)sdkError:(NSInteger)code format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString* error = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [[NSError alloc] initWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:code userInfo:@{NSLocalizedDescriptionKey: error}];
}

- (instancetype)initWithSettings:(OKSDKInitSettings *)settings {
    if(self = [super init]) {
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

- (void)openInSafari:(NSURL *)url success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    @synchronized(self) {
        if( [[self.safariVC view] superview] ) {
            return errorBlock([OKConnection sdkError:OKSDKErrorCodeUserConfirmationDialogAlreadyInProgress format:@"user confirmation dialog is already in progress"]);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *hostController = self.settings.controllerHandler();
            UIViewController  *vc;
#ifdef __IPHONE_9_0
            if (kIOS9x) {
                vc = [[OKSFSafariViewController alloc] initWithErrorBlock:errorBlock url:url];
                [hostController presentViewController:vc animated:true completion:nil];
                self.safariVC = vc;
            } else {
               [[UIApplication sharedApplication] openURL: url];
            }
#else
            [[UIApplication sharedApplication] openURL: url];
#endif

        });
    }
}


- (BOOL)openUrl:(NSURL *)url {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.safariVC dismissViewControllerAnimated:YES completion:nil];
    });
    NSString *key = [[url absoluteString] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#?"]][0];
    OKCompletitionHander completitionHander = self.completitionHandlers[key];
    NSDictionary *answer = [url ok_params];
    if(completitionHander) {
        [self.completitionHandlers removeObjectForKey:key];
        completitionHander(answer, [answer ok_error]);
        return YES;
    } else if([key isEqualToString:self.oauthRedirectUri]) {
        if (![answer ok_error]) {
            [self saveTokens:answer];
        }
        return YES;
    }
    return NO;
}

- (void)authorizeWithPermissions:(NSArray *)permissions success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if (self.accessToken && self.accessTokenSecretKey) {
        return successBlock(@[self.accessToken, self.accessTokenSecretKey]);
    }

    UIApplication *app = [UIApplication sharedApplication];
    if (![NSBundle ok_hasRegisteredURLScheme:self.oauthRedirectScheme]) {
        return errorBlock([OKConnection sdkError:OKSDKErrorCodeNoSchemaRegistered format:@"%@ schema should be registered for current app", self.oauthRedirectUri]);
    }
    NSString *queryString = [@{@"response_type":@"token",@"client_id":self.settings.appId,@"redirect_uri":[self.oauthRedirectUri ok_encode],@"layout":@"a",@"scope":[[permissions componentsJoinedByString:@";"] ok_encode]} ok_queryString];
    NSURL *appUrl = [NSURL URLWithString: [NSString stringWithFormat:@"%@?%@",OK_OAUTH_APP_URL,queryString]];
    __weak typeof(self) wSelf = self;
    self.completitionHandlers[self.oauthRedirectUri] = ^(NSDictionary *data, NSError *error) {
        if(error) {
            errorBlock(error);
        } else {
            [wSelf saveTokens:data];
            if(wSelf.accessToken || wSelf.accessTokenSecretKey) {
                successBlock(@[wSelf.accessToken, wSelf.accessTokenSecretKey]);
            } else {
                errorBlock(error);
            }
        }
    };
    if (![app openURL: appUrl]) {
        [self openInWebView:url success:successBlock error:errorBlock];
    }
}

- (void)saveTokens:(NSDictionary *)data {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:(self.accessToken = data[@"access_token"]) forKey:OK_USER_DEFS_ACCESS_TOKEN];
    [userDefaults setObject:(self.accessTokenSecretKey = data[@"session_secret_key"]) forKey:OK_USER_DEFS_SECRET_KEY];
    [userDefaults synchronize];
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

- (void)showWidget:(NSString *)command arguments:(NSDictionary *)arguments options:(NSDictionary *)options success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    NSString *returnUri = [NSString stringWithFormat:@"ok%@://%@",self.settings.appId, command];
    NSString *widgetUrl = [NSString stringWithFormat:@"%@%@&%@%@",OK_WIDGET_URL,[command ok_encode],[[arguments ok_union: @{@"st.redirect_uri":returnUri}]ok_queryStringWithSignature:self.accessTokenSecretKey sigName:@"st.signature"],[[options ok_union: @{@"st.access_token":self.accessToken,@"st.app":self.settings.appId,@"st.nocancel":@"on"}] ok_queryString]];
    self.completitionHandlers[returnUri] = ^(id data, NSError *error) {
        if(error) {
            errorBlock(error);
        } else {
            successBlock(data);
        }
    };
    [self openInSafari:[NSURL URLWithString:widgetUrl] success: successBlock error: errorBlock];
}

- (void)shutdown {
    [self.queue cancelAllOperations];
    [self.safariVC dismissViewControllerAnimated:NO completion:nil];
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

@implementation OKSDK

static OKConnection *connection;

+ (BOOL)openUrl:(NSURL *)url {
    return [connection openUrl:url];
}

+ (void)initWithSettings:(OKSDKInitSettings *)settings {
    connection = [[OKConnection alloc] initWithSettings: settings];
}

+ (void)authorizeWithPermissions:(NSArray *)permissions success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if(connection) {
        [connection authorizeWithPermissions:permissions success:successBlock error:errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{}]);
    }
}

+ (void)invokeMethod:(NSString *)method arguments:(NSDictionary *)arguments success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if(connection) {
        [connection invokeMethod:method arguments:arguments session: true signed: true success:successBlock error:errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{NSLocalizedDescriptionKey: OK_SDK_NOT_INIT_COMMON_ERROR}]);
    }
}

+ (void)shutdown {
    [connection shutdown];
}

+ (void)showWidget:(NSString *)command arguments:(NSDictionary *)arguments options:(NSDictionary *)options success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if(connection) {
        [connection showWidget:command arguments:arguments options:options success: successBlock error: errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{NSLocalizedDescriptionKey: OK_SDK_NOT_INIT_COMMON_ERROR}]);
    }
}

+ (void)invokeSdkMethod:(NSString *)method arguments:(NSDictionary *)arguments success:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    if(connection && connection.sdkToken) {
        [connection invokeMethod:method arguments:[@{@"sdkToken":connection.sdkToken} ok_union: arguments] session:true signed: true success:successBlock error:errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{NSLocalizedDescriptionKey: @"OKSDK not initialized you should call initWithAppIdAndAppKey and sdkInit first"}]);
    }
}





+ (void)sdkInit:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    NSString *deviceId = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    NSError *error;
    NSString *sessionData = [ @{@"version":@"2",@"device_id":deviceId,@"client_type":@"SDK_IOS",@"client_version":OK_SDK_VERSION} ok_json:error];
    if (error) {
        return errorBlock(error);
    }
    if (connection) {
        [connection invokeMethod:@"sdk.init" arguments:@{@"session_data": sessionData} session: false signed: false success:^(id data) {
            connection.sdkToken = data[@"session_key"];
            successBlock(data);
        } error:errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{NSLocalizedDescriptionKey: OK_SDK_NOT_INIT_COMMON_ERROR}]);
    }
}

+ (void)getInstallSource:(OKResultBlock)successBlock error:(OKErrorBlock)errorBlock {
    NSString *deviceId = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    if (connection) {
        [connection invokeMethod:@"sdk.getInstallSource" arguments:@{@"adv_id" : deviceId} session:false signed:false success:^(id data) {
            successBlock(data);
        } error:errorBlock];
    } else {
        errorBlock([NSError errorWithDomain:OK_SDK_ERROR_CODE_DOMAIN code:OKSDKErrorCodeNotIntialized userInfo:@{NSLocalizedDescriptionKey : OK_SDK_NOT_INIT_COMMON_ERROR}]);
    }
}


+ (void)clearAuth {
    [connection clearAuth];
}

+ (NSString *)currentAccessToken{
    if (connection){
        return connection.accessToken;
    }else{
        return nil;
    }
}

+ (NSString *)currentAccessTokenSecretKey{
    if (connection){
        return connection.accessTokenSecretKey;
    }else{
        return nil;
    }
}

@end
