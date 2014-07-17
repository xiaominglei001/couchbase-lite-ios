//
//  CBIndexedJSONDict.m
//  CBJSON
//
//  Created by Jens Alfke on 12/30/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "CBIndexedJSONDict.h"
#import "CBIndexedJSONEncoder.h"
#import "CBIndexedJSONFormat.h"
#import "CBLCollateJSON.h"


#define UU __unsafe_unretained


@implementation CBIndexedJSONDict
{
    const DictHeader* _header;
    NSData* _data;
    const uint8_t* _json;
    NSMutableDictionary* _cache;
    BOOL _hasAddedValues;
    BOOL _addToCache;
    NSUInteger _count;
}


- (id) initWithData: (UU NSData*)indexedJSONData
       addingValues: (UU NSMutableDictionary*)dictToAdd
        cacheValues: (BOOL)cacheValues
{
    NSParameterAssert(indexedJSONData);
    self = [super init];
    if (self) {
        if (![CBIndexedJSONEncoder isValidIndexedJSON: indexedJSONData]) {
            // If this is regular ol' JSON, fall back to NSJSONSerialization:
            if (indexedJSONData.length < 2 || ((const char*)indexedJSONData.bytes)[0] != '{')
                return nil;
            NSDictionary* dict = [NSJSONSerialization JSONObjectWithData: indexedJSONData
                                                                 options: 0 error: NULL];
            if (![dict isKindOfClass: [NSDictionary class]])
                return nil;
            if (dictToAdd.count == 0)
                return (id)dict;
            NSMutableDictionary* mdict = [dict mutableCopy];
            [mdict addEntriesFromDictionary: dictToAdd];
            return (id)mdict;
        }

        _data = [indexedJSONData copy];
        _header = (const DictHeader*)_data.bytes;
        UInt16 count = NSSwapBigShortToHost(_header->count);
        _json = (const uint8_t*)&_header->entry[count];
        _addToCache = cacheValues;
        if (dictToAdd.count > 0) {
            _hasAddedValues = YES;
            _cache = dictToAdd; // not copied, to save time
        } else if (cacheValues) {
            _cache = [[NSMutableDictionary alloc] init];
        }
    }
    return self;
}


+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    return [[self alloc] initWithData: data addingValues: nil cacheValues: YES];
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


@synthesize JSONData=_data;


- (const uint8_t*) _findValueFor:(UU id)key end: (const uint8_t**)endOfValue {
    NSParameterAssert(key != nil);
    __block const uint8_t* result = NULL;
    CBWithStringBytes(key, ^(const char *keyUTF8, size_t keyUTF8Len) {
        uint16_t hash = NSSwapHostShortToBig(CBJSONKeyHash(keyUTF8, keyUTF8Len));
        const DictEntry* entry = _header->entry;
        const uint8_t* jsonKey = _json;
        for (NSUInteger i = NSSwapBigShortToHost(_header->count); i > 0; i--, entry++) {
            jsonKey += NSSwapBigShortToHost(entry->offset);
            if (entry->hash == hash) {
                // Hash code matches entry; now compare the key strings:
                const uint8_t* jsonValue = matchString(jsonKey, keyUTF8, keyUTF8Len);
                if (jsonValue) {
                    // Keys match! Find the byte range of the value:
                    jsonValue++; // skip the ':'
                    if (i > 1)
                        *endOfValue = jsonKey + NSSwapBigShortToHost((entry+1)->offset) - 1;
                    else
                        *endOfValue = _data.bytes + _data.length - 1;
                    result = jsonValue; // found it!
                    return;
                }
            }
        }
    });
    return result;
}


- (BOOL)containsValueForKey:(UU NSString *)key {
    const uint8_t* end;
    return _cache[key] != nil || [self _findValueFor: key end: &end] != NULL;
}


- (NSUInteger) count {
    if (_count == 0) {
        _count = NSSwapBigShortToHost(_header->count);
        if (_hasAddedValues) {
            for (NSString* key in _cache) {
                const uint8_t* end;
                if ([self _findValueFor: key end: &end] == NULL)
                    _count++;
            }
        }
    }
    return _count;
}


- (id) objectForKey:(UU id)key {
    id value = _cache[key];
    if (value)
        return value;
    if (!key || ![key isKindOfClass: [NSString class]])
        return nil;

    const uint8_t* endOfValue;
    const uint8_t* jsonValue = [self _findValueFor: key end: &endOfValue];
    if (!jsonValue)
        return nil; // not present

    if (jsonValue[0] == '"') {
        const char* pos = (const char*)jsonValue;
        value = CBLParseJSONString(&pos, YES);
        if (_addToCache && value)
            _cache[key] = value;
    } else if (isdigit(jsonValue[0]) || jsonValue[0] == '-') {
        char* end;
        double num = strtod((const char*)jsonValue, &end);
        value = @(num);
    } else if (jsonValue[0] == 't') {
        value = @YES;
    } else if (jsonValue[0] == 'f') {
        value = @NO;
    } else {
        NSData* valueData = [[NSData alloc] initWithBytesNoCopy: (void*)jsonValue
                                                         length: endOfValue - jsonValue
                                                   freeWhenDone: NO];
        if (!valueData)
            return nil;
        NSError* error;
        value = [NSJSONSerialization JSONObjectWithData: valueData
                                                options: NSJSONReadingAllowFragments
                                                  error: &error];
        if (_addToCache && value)
            _cache[key] = value;
    }

    if (!value)
        NSLog(@"WARNING: CBLIndexedJSONDict: Unparseable JSON value for key \"%@\"", key);
    return value;
}


- (void) forEachKey: (void(^)(NSString*))block {
    const DictEntry* entry = _header->entry;
    const uint8_t* jsonKey = _json;
    for (NSUInteger i = NSSwapBigShortToHost(_header->count); i > 0; i--, entry++) {
        jsonKey += NSSwapBigShortToHost(entry->offset);
        const char* start = (const char*)jsonKey;
        NSString* key = CBLParseJSONString(&start, YES);
        if (key)
            block(key);
        else
            Warn(@"CBIndexedJSONDict: Couldn't read key at %p", jsonKey);
    }

    if (_hasAddedValues) {
        for (NSString* key in _cache) {
            const uint8_t* end;
            if ([self _findValueFor: key end: &end] == NULL)
                block(key);
        }
    }
}


- (NSArray*) allKeys {
    NSMutableArray* keys = [NSMutableArray arrayWithCapacity: _header->count];
    [self forEachKey:^(NSString *key) {
        [keys addObject: key];
    }];
    return keys;
}


- (NSEnumerator *)keyEnumerator {
    return self.allKeys.objectEnumerator;
}


// This is what the %@ substitution calls.
- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level {
    NSMutableString* desc = [@"{\n" mutableCopy];
    [self forEachKey:^(NSString *key) {
        NSString* valStr;
        char delim = '=';
        const uint8_t* jsonEnd;
        const uint8_t* jsonStr = [self _findValueFor: key end: &jsonEnd];
        if (jsonStr) {
            valStr = [[NSString alloc] initWithBytes: jsonStr length: jsonEnd-jsonStr
                                            encoding: NSUTF8StringEncoding];
            delim = ':';
            if (_cache[key])
                delim = '-';
        } else {
            id value = self[key];
            if ([value respondsToSelector: @selector(descriptionWithLocale:indent:)])
                valStr = [value descriptionWithLocale: locale indent:level+1];
            else if ([value respondsToSelector: @selector(descriptionWithLocale:)])
                valStr = [value descriptionWithLocale: locale];
            else
                valStr = [value description];
        }
        [desc appendFormat: @"    \"%@\" %c %@,\n", key, delim, valStr];
    }];
    [desc appendString: @"}"];
    return desc;
}


// Compares a JSON string to a UTF-8 string. jsonKey points to the opening quote character.
// Returns a pointer to the byte past the closing quote character on match, or NULL on mismatch.
static const uint8_t* matchString(const uint8_t* jsonKey, const char *utf8, size_t utf8Len) {
    size_t keyUTF8Index = 0;
    const uint8_t* pos = jsonKey + 1; // skip opening quote
    while (*pos != '"') {
        //TODO: Interpret "\" character!!
        if (keyUTF8Index >= utf8Len || *pos != utf8[keyUTF8Index])
            return NULL; // doesn't match
        keyUTF8Index++;
        pos++;
    }
    if (keyUTF8Index != utf8Len)
        return NULL;
    return pos + 1; // match!
}


@end
