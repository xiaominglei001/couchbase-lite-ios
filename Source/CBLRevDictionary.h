//
//  CBLRevDictionary.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** A proxy dictionary that wraps an NSDictionary and adds "_id", "_rev" and maybe "_deleted"
    keys/values. */
@interface CBLRevDictionary : NSDictionary

- (instancetype) initWithDictionary: (NSDictionary*)dict
                              docID: (NSString*)docID
                              revID: (NSString*)revID
                            deleted: (BOOL)deleted;

- (void) _setLocalSeq: (uint64_t)seq;
- (void) _setConflicts: (NSArray*)conflicts;

@end
