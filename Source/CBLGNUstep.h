//
//  CBLGNUstep.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#ifdef GNUSTEP

/* Stuff that's in iOS / OS X but not GNUstep or Linux */

#define _GNU_SOURCE

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

#ifndef FOUNDATION_EXTERN
#if defined(__cplusplus)
#define FOUNDATION_EXTERN extern "C"
#else
#define FOUNDATION_EXTERN extern
#endif
#endif

#ifndef NS_BLOCKS_AVAILABLE
#define NS_BLOCKS_AVAILABLE 1
#endif


#define __unused __attribute__((unused))


typedef int32_t SInt32;
typedef uint32_t UInt32;
typedef int64_t SInt64;
typedef uint64_t UInt64;
typedef int8_t SInt8;
typedef uint8_t UInt8;


// in BSD but not Linux:
int digittoint(int c);
size_t strlcat(char *dst, const char *src, size_t siz);


typedef double CFAbsoluteTime;
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);


#define CF_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NS_ENUM CF_ENUM
#define CF_OPTIONS CF_ENUM
#define NS_OPTIONS CF_OPTIONS

#ifndef CF_RETURNS_RETAINED
#if __has_feature(attribute_cf_returns_retained)
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#else
#define CF_RETURNS_RETAINED
#endif
#endif

#ifndef CF_CONSUMED
#if __has_feature(attribute_cf_consumed)
#define CF_CONSUMED __attribute__((cf_consumed))
#else
#define CF_CONSUMED
#endif
#endif

inline CF_RETURNS_RETAINED CFTypeRef CFBridgingRetain(id X) {
    return (__bridge_retained CFTypeRef)X;
}

inline id CFBridgingRelease(CFTypeRef CF_CONSUMED X) {
    return (__bridge_transfer id)X;
}

#undef NSAssert
#define NSAssert(condition, desc, ...)	\
    do {				\
	if (!(condition)) {		\
	    [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd \
		object:self file:[NSString stringWithUTF8String:__FILE__] \
	    	lineNumber:__LINE__ description:(desc), ##__VA_ARGS__]; \
	}				\
    } while(0)

#undef NSCAssert
#define NSCAssert(condition, desc, ...) \
    do {				\
	if (!(condition)) {		\
	    [[NSAssertionHandler currentHandler] handleFailureInFunction:[NSString stringWithUTF8String:__PRETTY_FUNCTION__] \
		file:[NSString stringWithUTF8String:__FILE__] \
	    	lineNumber:__LINE__ description:(desc), ##__VA_ARGS__]; \
	}				\
    } while(0)


#define NS_REQUIRES_PROPERTY_DEFINITIONS


#define NSRunLoopCommonModes NSDefaultRunLoopMode


typedef NS_OPTIONS(NSUInteger, NSDataReadingOptions) {
    NSDataReadingMappedIfSafe =   1UL << 0,	// Hint to map the file in if possible and safe
    NSDataReadingUncached = 1UL << 1,	// Hint to get the file not to be cached in the kernel
    NSDataReadingMappedAlways = 1UL << 3,	// Hint to map the file in if possible. This takes precedence over NSDataReadingMappedIfSafe if both are given.
};

typedef NS_OPTIONS(NSUInteger, NSDataWritingOptions) {
    NSDataWritingAtomic = 1UL << 0,	// Hint to use auxiliary file when saving; equivalent to atomically:YES
    NSDataWritingWithoutOverwriting = 1UL << 1, // Hint to  prevent overwriting an existing file. Cannot be combined with NSDataWritingAtomic.
};

enum {
    NSDataSearchBackwards = 1UL << 0,
    NSDataSearchAnchored = 1UL << 1
};
typedef NSUInteger NSDataSearchOptions;

@interface NSData (GNUstep)
+ (id)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
- (NSRange)rangeOfData:(NSData *)dataToFind options:(NSDataSearchOptions)mask range:(NSRange)searchRange;
@end


@interface NSString (GNUstep)
- (BOOL)getBytes:(void *)buffer maxLength:(NSUInteger)maxBufferCount usedLength:(NSUInteger *)usedBufferCount encoding:(NSStringEncoding)encoding options:(NSStringEncodingConversionOptions)options range:(NSRange)range remainingRange:(NSRangePointer)leftover;
@end


@interface NSFileManager (GNUstep)
- (NSArray *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
@end


@interface NSURL (GNUstep)
- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent;
- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent isDirectory:(BOOL)isDirectory;
@end


@interface NSOperationQueue (GNUstep)
- (void)addOperationWithBlock:(void (^)(void))block;
@end


@protocol NSURLConnectionDelegate <NSObject>
@end


@protocol NSStreamDelegate <NSObject>
@end


enum {
    NSURLErrorClientCertificateRequired = -1206,
    NSURLRequestReloadIgnoringLocalCacheData = NSURLRequestReloadIgnoringCacheData
};


typedef struct _CFHTTPMessage *CFHTTPMessageRef;
typedef struct _SecTrust *SecTrustRef;
typedef struct _SecCertificate *SecCertificateRef;


#endif // GNUSTEP
