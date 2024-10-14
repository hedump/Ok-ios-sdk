#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#import "OKSDK.h"
#ifdef __IPHONE_9_0
#import <SafariServices/SafariServices.h>
#endif

#import "OKSDK.h"

FOUNDATION_EXPORT double ok_ios_sdkVersionNumber;
FOUNDATION_EXPORT const unsigned char ok_ios_sdkVersionString[];
