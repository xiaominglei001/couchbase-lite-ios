//
//  CBLRevDictionary.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLRevDictionary.h"
extern "C" {
    #import "CBLInternal.h"
}


@implementation CBLRevDictionary
{
    NSDictionary* _dict;
    NSString* _docID;
    id _revID;
    BOOL _deleted;
    SequenceNumber _localSeq;
    NSArray *_conflicts;
}


- (instancetype) initWithDictionary: (NSDictionary*)dict
                              docID: (NSString*)docID
                              revID: (id)revID
                            deleted: (BOOL)deleted
{
    NSParameterAssert(dict && docID && revID);
    DAssert(!dict[@"_id"]);
    DAssert(!dict[@"_rev"]);
    DAssert(!dict[@"_deleted"]);
    self = [super init];
    if (self) {
        _dict = [dict copy];
        _docID = [docID copy];
        _revID = revID;
        _deleted = deleted;
    }
    return self;
}

- (void) _setLocalSeq: (uint64_t)seq {
    _localSeq = seq;
}

- (void) _setConflicts:(NSArray *)conflicts {
    _conflicts = conflicts;
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (NSMutableDictionary*) mutableCopy {
    NSMutableDictionary* m = [_dict mutableCopy] ?: [[NSMutableDictionary alloc] init];
    m[@"_id"] = _docID;
    m[@"_rev"] = self.cbl_rev;
    if (_deleted)
        m[@"_deleted"] = @YES;
    if (_localSeq)
        m[@"_local_seq"] = @(_localSeq);
    if (_conflicts)
        m[@"_conflicts"] = _conflicts;
    return m;
}


- (NSUInteger) count {
    return _dict.count + (_deleted ? 3 : 2) + (_localSeq > 0) + (_conflicts != nil);
}


- (NSUInteger) hash {
    return _dict.hash ^ _docID.hash;
}


- (id) objectForKey: (UU id)key {
    id o = [_dict objectForKey: key];
    if (o)
        return o;
    else if ([key isEqualToString: @"_id"])
        return _docID;
    else if ([key isEqualToString: @"_rev"])
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


- (NSArray*) allKeys {
    NSMutableArray* keys = _dict ? [_dict.allKeys mutableCopy] : [NSMutableArray array];
    [keys addObject: @"_id"];
    [keys addObject: @"_rev"];
    if (_deleted)
        [keys addObject: @"_deleted"];
    if (_localSeq)
        [keys addObject: @"_local_seq"];
    if (_conflicts)
        [keys addObject: @"_conflicts"];
    return keys;
}


- (NSEnumerator *)keyEnumerator {
    return self.allKeys.objectEnumerator;
}


- (NSString*) cbl_id                {return _docID;}
- (NSString*) cbl_rev               {return _revID;}
- (BOOL) cbl_deleted                {return _deleted;}


@end
