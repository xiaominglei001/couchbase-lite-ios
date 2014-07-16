//
//  CBJSONEncoder.m
//  CBJSON
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "CBJSONEncoder.h"
#include "yajl/yajl_gen.h"


@implementation CBJSONEncoder
{
    NSMutableData* _encoded;
    yajl_gen _gen;
    yajl_gen_status _status;
}


@synthesize canonical=_canonical;


+ (NSData*) encode: (id)object error: (NSError**)outError {
    CBJSONEncoder* encoder = [[self alloc] init];
    if ([encoder encode: object])
        return encoder.encodedData;
    else if (outError)
        *outError = encoder.error;
    return nil;
}

+ (NSData*) canonicalEncoding: (id)object error: (NSError**)outError {
    CBJSONEncoder* encoder = [[self alloc] init];
    encoder.canonical = YES;
    if ([encoder encode: object])
        return encoder.encodedData;
    else if (outError)
        *outError = encoder.error;
    return nil;
}


- (instancetype) init {
    self = [super init];
    if (self) {
        _encoded = [NSMutableData dataWithCapacity: 1024];
        _gen = yajl_gen_alloc(NULL);
        if (!_gen)
            return nil;
    }
    return self;
}


- (void) dealloc {
    if (_gen)
        yajl_gen_free(_gen);
}


- (BOOL) encode: (id)object {
    return [self encodeNestedObject: object];
}


- (NSData*) encodedData {
    const uint8_t* buf;
    size_t len;
    yajl_gen_get_buf(_gen, &buf, &len);
    [_encoded appendBytes: buf length: len];
    yajl_gen_clear(_gen);
    return _encoded;
}

- (NSMutableData*) output {
    [self encodedData];
    return _encoded;
}


- (BOOL) encodeNestedObject: (__unsafe_unretained id)object {
    if ([object isKindOfClass: [NSString class]]) {
        return [self encodeString: object];
    } else if ([object isKindOfClass: [NSDictionary class]]) {
        return [self encodeDictionary: object];
    } else if ([object isKindOfClass: [NSNumber class]]) {
        return [self encodeNumber: object];
    } else if ([object isKindOfClass: [NSArray class]]) {
        return [self encodeArray: object];
    } else if ([object isKindOfClass: [NSNull class]]) {
        return [self encodeNull];
    } else {
        return NO;
    }
}


- (BOOL) encodeString: (__unsafe_unretained NSString*)str {
    __block yajl_gen_status status = yajl_gen_invalid_string;
    CBWithStringBytes(str, ^(const char *chars, size_t len) {
        status = yajl_gen_string(_gen, (const unsigned char*)chars, len);
    });
    return [self checkStatus: status];
}


- (BOOL) encodeNumber: (__unsafe_unretained NSNumber*)number {
    yajl_gen_status status;
    switch (number.objCType[0]) {
        case 'c':
            status = yajl_gen_bool(_gen, number.boolValue);
            break;
        case 'f':
        case 'd':
            status = yajl_gen_double(_gen, number.doubleValue);
            break;
        case 'Q': {
            char str[32];
            unsigned len = sprintf(str, "%llu", number.unsignedLongLongValue);
            status = yajl_gen_number(_gen, str, len);
            break;
        }
        default:
            status = yajl_gen_integer(_gen, number.longLongValue);
            break;
    }
    return [self checkStatus: status];
}


- (BOOL) encodeNull {
    return [self checkStatus: yajl_gen_null(_gen)];
}


- (BOOL) encodeArray: (__unsafe_unretained NSArray*)array {
    yajl_gen_array_open(_gen);
    for (id item in array)
        if (![self encodeNestedObject: item])
            return NO;
    return [self checkStatus: yajl_gen_array_close(_gen)];
}


- (BOOL) encodeDictionary: (__unsafe_unretained NSDictionary*)dict {
    if (![self checkStatus: yajl_gen_map_open(_gen)])
        return NO;
    id keys = dict;
    if (_canonical)
        keys = [[self class] orderedKeys: dict];
    for (NSString* key in keys)
        if (![self encodeKey: key value: dict[key]])
            return NO;
    return [self checkStatus: yajl_gen_map_close(_gen)];
}

- (BOOL) encodeKey: (__unsafe_unretained id)key value: (__unsafe_unretained id)value {
    return [self encodeNestedObject: key] && [self encodeNestedObject: value];
}

+ (NSArray*) orderedKeys: (__unsafe_unretained NSDictionary*)dict {
    return [[dict allKeys] sortedArrayUsingComparator: ^NSComparisonResult(id s1, id s2) {
        return [s1 compare: s2 options: NSLiteralSearch];
        /* Alternate implementation in case NSLiteralSearch turns out to be inappropriate:
         NSUInteger len1 = [s1 length], len2 = [s2 length];
         unichar chars1[len1], chars2[len2];     //FIX: Will crash (stack overflow) on v. long strings
         [s1 getCharacters: chars1 range: NSMakeRange(0, len1)];
         [s2 getCharacters: chars2 range: NSMakeRange(0, len2)];
         NSUInteger minLen = MIN(len1, len2);
         for (NSUInteger i=0; i<minLen; i++) {
         if (chars1[i] > chars2[i])
         return 1;
         else if (chars1[i] < chars2[i])
         return -1;
         }
         // All chars match, so the longer string wins
         return (NSInteger)len1 - (NSInteger)len2; */
    }];
}


- (BOOL) checkStatus: (yajl_gen_status)status {
    if (status == yajl_gen_status_ok)
        return YES;
    _status = status;
    return NO;
}


- (NSError*) error {
    if (_status == yajl_gen_status_ok)
        return nil;
    return [NSError errorWithDomain: @"YAJL" code: _status userInfo: nil];
}


BOOL CBWithStringBytes(__unsafe_unretained NSString* str, void (^block)(const char*, size_t)) {
    // First attempt: Get a C string directly from the CFString if it's in the right format:
    const char* cstr = CFStringGetCStringPtr((CFStringRef)str, kCFStringEncodingUTF8);
    if (cstr) {
        block(cstr, strlen(cstr));
        return YES;
    }

    NSUInteger byteCount;
    if (str.length < 256) {
        // First try to copy the UTF-8 into a smallish stack-based buffer:
        char stackBuf[256];
        NSRange remaining;
        BOOL ok = [str getBytes: stackBuf maxLength: sizeof(stackBuf) usedLength: &byteCount
                       encoding: NSUTF8StringEncoding options: 0
                          range: NSMakeRange(0, str.length) remainingRange: &remaining];
        if (ok && remaining.length == 0) {
            block(stackBuf, byteCount);
            return YES;
        }
    }

    // Otherwise malloc a buffer to copy the UTF-8 into:
    NSUInteger maxByteCount = [str maximumLengthOfBytesUsingEncoding: NSUTF8StringEncoding];
    char* buf = malloc(maxByteCount);
    if (!buf)
        return NO;
    BOOL ok = [str getBytes: buf maxLength: maxByteCount usedLength: &byteCount
                   encoding: NSUTF8StringEncoding options: 0
                      range: NSMakeRange(0, str.length) remainingRange: NULL];
    if (ok)
        block(buf, byteCount);
    free(buf);
    return ok;
}


@end
