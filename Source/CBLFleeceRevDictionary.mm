//
//  CBLFleeceRevDictionary.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLFleeceRevDictionary.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "Encoder.hh"
#import "Value.hh"
#import "CBForest/RevID.hh"


using namespace fleece;


@interface CBLFleeceRevDictionary ()
- (instancetype) initWithDict: (const dict*)dict
                   fleeceData: (NSData*)fleeceData;
@end

@interface CBLFleeceArray : NSArray
- (instancetype) initWithArray: (const fleece::array*)arrayValue
                    fleeceData: (NSData*)fleeceData;
@end


static id objectForValue(const value* v, UU NSData* fleeceData) {
    if (!v)
        return nil;
    switch (v->type()) {
        case kArray:
            return [[CBLFleeceArray alloc] initWithArray: v->asArray() fleeceData: fleeceData];
        case kDict:
            return [[CBLFleeceRevDictionary alloc] initWithDict: v->asDict() fleeceData: fleeceData];
        default:
            return v->toNSObject(NULL);
    }
}


@implementation CBLFleeceRevDictionary
{
    NSData *_fleeceData;
    const dict* _dict;
    NSUInteger _count;

    NSString* _docID;
    id _revID;
    BOOL _deleted;
    SequenceNumber _localSeq;
    NSArray *_conflicts;
}


+ (id) objectWithFleeceData: (NSData*)fleece trusted: (BOOL)trusted {
    slice s(fleece);
    const value *root = trusted ? value::fromTrustedData(s) : value::fromData(s);
    return objectForValue(root, fleece);
}


+ (id) objectWithFleeceBytes: (const void*)bytes length: (NSUInteger)length trusted: (BOOL)trusted {
    slice s(bytes, length);
    const value *root = trusted ? value::fromTrustedData(s) : value::fromData(s);
    if (!root)
        return nil;
    auto type = root->type();
    if (type == kArray || type == kDict) {
        NSData *data = [NSData dataWithBytes: bytes length: length];
        return objectForValue(value::fromTrustedData(data), data);
    } else {
        return root->toNSObject();  // avoid creating NSData if we don't need it
    }
}


+ (NSData*) fleeceDataWithObject: (id)object {
    NSParameterAssert(object != nil);
    Writer writer;
    Encoder encoder(writer);
    encoder.write(object);
    encoder.end();
    return writer.extractOutput().convertToNSData();
}


- (instancetype) initWithDict: (const dict*)dict fleeceData: (UU NSData*)fleece {
    self = [super init];
    if (self) {
        _fleeceData = fleece;
        _dict = dict;
        _count = dict->count();
    }
    return self;
}

- (instancetype) initWithFleeceData: (UU NSData*)fleece
                            trusted: (BOOL)trusted
                              docID: (UU NSString*)docID
                              revID: (UU id)revID
                            deleted: (BOOL)deleted
{
    NSParameterAssert(fleece && docID && revID);

    slice data(fleece);
    const value *root = trusted ? value::fromTrustedData(data) : value::fromData(data);
    if (!root || !root->asDict())
        return nil;

    self = [self initWithDict: (const dict*)root fleeceData: fleece];
    if (self) {
        DAssert(!_dict->get(slice("_id")));
        DAssert(!_dict->get(slice("_rev")));
        DAssert(!_dict->get(slice("_deleted")));
        _count += 2 + (!!deleted);
        _docID = [docID copy];
        _revID = revID;
        _deleted = deleted;
    }
    return self;
}


- (void) _setLocalSeq: (uint64_t)seq {
    NSParameterAssert(seq != 0);
    _localSeq = seq;
    ++_count;
}

- (void) _setConflicts:(UU NSArray *)conflicts {
    NSParameterAssert(conflicts != nil);
    _conflicts = conflicts;
    ++_count;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}

- (NSMutableDictionary*) mutableCopy {
    NSMutableDictionary* m = [[NSMutableDictionary alloc] initWithCapacity: _count];
    [self forEachKey:^(NSString *key, const fleece::value *v, id object, BOOL *stop) {
        if (!object)
            object = objectForValue(v, _fleeceData);
        m[key] = object;
    }];
    return m;
}

- (NSUInteger) count {
    return _count;
}

- (NSUInteger) hash {
    return _fleeceData.hash ^ _docID.hash;
}


- (id) objectForKey: (UU id)key {
    if (![key isKindOfClass: [NSString class]])
        return nil;
    const value* v = _dict->get((NSString*)key);
    if (v)
        return objectForValue(v, _fleeceData);
    else if (_docID && [key isEqualToString: @"_id"])
        return _docID;
    else if (_revID && [key isEqualToString: @"_rev"])
        return self.cbl_rev;
    else if (_deleted && [key isEqualToString: @"_deleted"])
        return @YES;
    else if (_localSeq && [key isEqualToString: @"_local_seq"])
        return @(_localSeq);
    else if (_conflicts && [key isEqualToString: @"_conflicts"])
        return _conflicts;
    else
        return nil;
}


- (BOOL) forEachKey: (void(^)(NSString*, const value*, id obj, BOOL*))block {
    BOOL stop = NO;
    for (dict::iterator iter(_dict); iter; ++iter) {
        block((NSString*)iter.key()->asString(), iter.value(), nil, &stop);
        if (stop)
            return NO;
    }

    if (_docID) {
        block(@"_id", NULL, _docID, &stop);
        if (stop) return NO;
    }
    if (_revID) {
        block(@"_rev", NULL, self.cbl_rev, &stop);
        if (stop) return NO;
    }
    if (_deleted) {
        block(@"_deleted", NULL, @YES, &stop);
        if (stop) return NO;
    }
    if (_localSeq) {
        block(@"_local_seq", NULL, @(_localSeq), &stop);
        if (stop) return NO;
    }
    if (_conflicts) {
        block(@"_deleted", NULL, _conflicts, &stop);
        if (stop) return NO;
    }
    return YES;
}


- (NSArray*) allKeys {
    NSMutableArray* keys = [NSMutableArray arrayWithCapacity: _dict->count()];
    [self forEachKey: ^(UU NSString *key, const value* v, UU id, BOOL* stop) {
        [keys addObject: key];
    }];
    return keys;
}


- (NSEnumerator *)keyEnumerator {
    return self.allKeys.objectEnumerator;
}


- (void) enumerateKeysAndObjectsUsingBlock: (void (^)(UU id key, UU id obj, BOOL *stop))block {
    [self forEachKey:^(UU NSString* key, const value* v, id object, BOOL* stop) {
        if (!object)
            object = objectForValue(v, _fleeceData);
        block(key, object, stop);
    }];
}


- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState *)state
                                   objects: (id __unsafe_unretained [])stackBuf
                                     count: (NSUInteger)stackBufCount
{
    NSUInteger index = state->state;
    if (index == 0)
        state->mutationsPtr = &state->extra[0]; // this has to be pointed to something non-NULL

    NSUInteger n = 0;
    if (index < _dict->count()) {
        auto iter = _dict->begin();
        iter += (uint32_t)index;
        for (; iter; ++iter) {
            NSString* key = (NSString*)iter.key()->asString();
            CFAutorelease(CFBridgingRetain(key)); // keep key from being dealloced on return
            stackBuf[n++] = key;
            if (n >= stackBufCount)
                break;
        }
    } else if (index < _count) {
        DAssert(stackBufCount >= 5);
        if (_docID)
            stackBuf[n++] = @"_id";
        if (_revID)
            stackBuf[n++] = @"_rev";
        if (_deleted)
            stackBuf[n++] = @"_deleted";
        if (_localSeq)
            stackBuf[n++] = @"_local_seq";
        if (_conflicts)
            stackBuf[n++] = @"_conflicts";
    }

    state->itemsPtr = stackBuf;
    state->state += n;
    return n;
}


- (BOOL) cbl_deleted                {return _deleted || super.cbl_deleted;}
- (NSString*) cbl_id                {return _docID ?: super.cbl_id;}

- (NSString*) cbl_rev {
    if ([_revID isKindOfClass: [NSData class]]) {
        // Converting from forestdb::revID to NSString is sort of expensive, so defer it
        forestdb::revid rev((NSData*)_revID);
        _revID = (NSString*)rev;
    }
    return _revID ?: super.cbl_rev;
}

@end




#pragma mark - ARRAY:


@implementation CBLFleeceArray
{
    const array* _array;
    NSUInteger _count;
    NSData *_fleeceData;
}


- (instancetype) initWithArray: (const fleece::array*)arrayValue
                    fleeceData: (UU NSData*)fleeceData
{
    NSParameterAssert(arrayValue);
    self = [super init];
    if (self) {
        _array = arrayValue;
        _count = _array->count();
        _fleeceData = fleeceData;
    }
    return self;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (NSMutableArray*) mutableCopy {
    NSMutableArray* m = [[NSMutableArray alloc] initWithCapacity: _count];
    for (array::iterator iter(_array); iter; ++iter) {
        [m addObject: objectForValue(iter.value(), _fleeceData)];
    }
    return m;
}


- (NSUInteger) count {
    return _count;
}


- (id) objectAtIndex: (NSUInteger)index {
    if (index >= _count)
        [NSException raise: NSRangeException format: @"Array index out of range"];
    auto v = _array->get((uint32_t)index);
    return objectForValue(v, _fleeceData);
}


// Fast enumeration -- for(in) loops use this.
- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState *)state
                                   objects: (id __unsafe_unretained [])stackBuf
                                     count: (NSUInteger)stackBufCount
{
    NSUInteger index = state->state;
    if (index == 0)
        state->mutationsPtr = &state->extra[0]; // this has to be pointed to something non-NULL
    if (index >= _count)
        return 0;

    auto iter = _array->begin();
    iter += (uint32_t)index;
    NSUInteger n = 0;
    for (; iter; ++iter) {
        id v = objectForValue(iter.value(), _fleeceData);
        Assert(v);
        CFAutorelease(CFBridgingRetain(v));
        stackBuf[n++] = v;
        if (n >= stackBufCount)
            break;
    }

    state->itemsPtr = stackBuf;
    state->state += n;
    return n;
}


// This is what the %@ substitution calls.
- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level {
    NSMutableString* desc = [@"[\n" mutableCopy];
    for (auto iter = _array->begin(); iter; ++iter) {
        NSString* valStr = (NSString*)iter->toJSON();
        [desc appendFormat: @"    %@,\n", valStr];
    };
    [desc appendString: @"]"];
    return desc;
}


@end
