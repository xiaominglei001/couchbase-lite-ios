//
//  CBLFleeceRevDictionary.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CBLFleeceRevDictionary : NSDictionary

- (instancetype) initWithFleeceData: (NSData*)fleece
                            trusted: (BOOL)trusted
                              docID: (NSString*)docID
                              revID: (id)revID
                            deleted: (BOOL)deleted;

// These should be called immediately after initialization:
- (void) _setLocalSeq: (uint64_t)seq;
- (void) _setConflicts:(NSArray *)conflicts;


+ (id) objectWithFleeceData: (NSData*)fleece
                    trusted: (BOOL)trusted;
+ (id) objectWithFleeceBytes: (const void*)bytes
                      length: (NSUInteger)length
                     trusted: (BOOL)trusted;

+ (NSData*) fleeceDataWithObject: (id)object;

@end
