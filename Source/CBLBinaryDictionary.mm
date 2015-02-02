//
//  CBLBinary.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/15.
//
//

#import "CBLBinaryDictionary.h"
extern "C" {
    #import "CBLJSON.h"
    #import "CBLMisc.h"
}
#import <CBForest/Encoding.hh>
#import <CBForest/EncodingWriter.hh>
#import <sstream>

using namespace forestdb;


@implementation CBLBinaryDictionary
{
    NSData* _binaryData;
    const dict* _dict;
    NSUInteger _count;
    NSMutableDictionary* _cache;
    BOOL _hasAddedValues;
    BOOL _addToCache;
}


+ (BOOL) isValidBinary: (UU NSData*)binary {
    return value::validate(slice(binary)) != NULL;
}

+ (NSData*) JSONToBinary: (UU NSData*)json {
    @autoreleasepool {
        id object = [CBLJSON JSONObjectWithData: json options: NSJSONReadingAllowFragments
                                          error: NULL];
        return [self objectToBinary: object];
    }
}

+ (NSData*) binaryToJSON: (UU NSData*)binary {
    return stringToData(((const value*)binary.bytes)->toJSON());
}

+ (NSData*) objectToBinary: (UU id)object {
    if ([object isKindOfClass: self])
        return [object binaryData];
    try {
        std::stringstream out;
        dataWriter writer(out);
        writer.write(object);
        return stringToData(out.str());
    } catch (...) {
        return nil;
    }
}

static inline NSData* stringToData(const std::string& str) {
    return [NSData dataWithBytes: str.data() length: str.size()];
}



- (instancetype) initWithBinary: (UU NSData*)binary
                   addingValues: (UU NSMutableDictionary*)dictToAdd
                    cacheValues: (BOOL)cacheValues
{
#if DEBUG
    Assert(value::validate(slice(binary)));
#endif
    return [self initWithBinary: [binary copy]
                           dict: NULL
                   addingValues: dictToAdd
                    cacheValues: cacheValues];
}


- (instancetype) initWithBinary: (UU NSData*)binary
                           dict: (const dict*)dictValue
                   addingValues: (UU NSMutableDictionary*)dictToAdd
                    cacheValues: (BOOL)cacheValues
{
    self = [super init];
    if (self) {
        _binaryData = binary;
        if (dictValue) {
            _dict = dictValue;
        } else {
            _dict = (const dict*)_binaryData.bytes;
            if (_dict->type() != kDict)
                return nil;
        }
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


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (NSData*) binaryData {
    if (_dict == _binaryData.bytes)
        return _binaryData;
    size_t length = (char*)_dict->next() - (char*)_dict;
    return [NSData dataWithBytes: _dict length: length];
}


- (const value*) _findValueFor:(UU id)key {
    if (![key isKindOfClass: [NSString class]])
        return NULL;
    __block const value* result;
    CBLWithStringBytes(key, ^(const char *keyUTF8, size_t keyUTF8Len) {
        result = _dict->get(slice(keyUTF8, keyUTF8Len));
    });
    return result;
}


- (NSUInteger) count {
    if (_count == 0) {
        _count = _dict->count();
        if (_hasAddedValues) {
            for (NSString* key in _cache) {
                if ([self _findValueFor: key] == NULL)
                    _count++;
            }
        }
    }
    return _count;
}


- (BOOL)containsValueForKey:(UU NSString *)key {
    return _cache[key] != nil || [self _findValueFor: key] != NULL;
}


- (id) objectForKey: (UU id)key {
    id object = _cache[key];
    if (object)
        return object;
    if (!key || ![key isKindOfClass: [NSString class]])
        return nil;

    const value* v = [self _findValueFor: key];
    if (v && v->type() == kDict) {
        object = [[CBLBinaryDictionary alloc] initWithBinary: _binaryData
                                                        dict: v->asDict()
                                                addingValues: nil
                                                 cacheValues: _addToCache];
    } else {
        object = v->asNSObject();
    }
    if (_addToCache && object)
        _cache[key] = object;
    return object;
}


- (void) forEachKey: (void(^)(NSString*, const value*, BOOL*))block {
    for (dict::iterator iter(_dict); iter; ++iter) {
        BOOL stop = NO;
        block(iter.key()->asNSObject(), iter.value(), &stop);
        if (stop)
            break;
    }
    if (_hasAddedValues) {
        for (NSString* key in _cache) {
            if ([self _findValueFor: key] == NULL) {
                BOOL stop = NO;
                block(key, NULL, &stop);
                if (stop)
                    return;
            }
        }
    }
}


- (NSArray*) allKeys {
    NSMutableArray* keys = [NSMutableArray arrayWithCapacity: _dict->count()];
    [self forEachKey:^(NSString *key, const value* v, BOOL* stop) {
        [keys addObject: key];
    }];
    return keys;
}


- (NSEnumerator *)keyEnumerator {
    return self.allKeys.objectEnumerator;
}


- (void) enumerateKeysAndObjectsUsingBlock: (void (^)(UU id key, UU id obj, BOOL *stop))block {
    [self forEachKey:^(NSString* key, const value* v, BOOL* stop) {
        id object = _cache[key];
        if (!object && v)
            object = v->asNSObject();
        if (object)
            block(key, object, stop);
    }];
}


/*
- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState *)state
                                   objects: (id __unsafe_unretained [])stackBuf
                                     count: (NSUInteger)stackBufCount
{
    NSUInteger index = state->state;
    NSUInteger endIndex = NSSwapBigShortToHost(_header->count);
    if (index >= endIndex)
        return 0;

    const uint8_t* jsonKey;
    if (index == 0)
        jsonKey = _json;
    else
        jsonKey = (void*)state->mutationsPtr;

    NSUInteger n = 0;
    for (const DictEntry* entry = &_header->entry[index]; index < endIndex; index++, entry++) {
        jsonKey += NSSwapBigShortToHost(entry->offset);
        const char* start = (const char*)jsonKey;
        NSString* key = CBLParseJSONString(&start, YES);
        if (key) {
            CFAutorelease(CFBridgingRetain(key));
            stackBuf[n++] = key;
        }
    }
    //FIX: This needs to return the added objects from _cache too

    state->mutationsPtr = (void*)jsonKey;
    state->itemsPtr = stackBuf;
    state->state = index;
    return n;
}
*/


// This is what the %@ substitution calls.
- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level {
    NSMutableString* desc = [@"{\n" mutableCopy];
    [self forEachKey: ^(NSString *key, const value* v, BOOL *stop) {
        NSString* valStr;
        char delim = '=';
        if (v) {
            valStr = [[NSString alloc] initWithUTF8String: v->toJSON().c_str()];
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


@end
