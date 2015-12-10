//
//  CBLForestBridge.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import <CBForest/CBForest.hh>
extern "C" {
#import <CBForest/CBForest.hh>
#import "CBL_Storage.h"
}
@class CBLSymmetricKey, CBLFleeceRevDictionary;


namespace couchbase_lite {
    CBLStatus tryStatus(CBLStatus(^block)());
    bool tryError(NSError** outError, void(^block)());
    CBLStatus CBLStatusFromForestDBStatus(int fdbStatus);
}


@interface CBLForestBridge : NSObject

+ (void) setEncryptionKey: (fdb_encryption_key*)fdbKey
         fromSymmetricKey: (CBLSymmetricKey*)key;

+ (forestdb::Database*) openDatabaseAtPath: (NSString*)path
                                withConfig: (forestdb::Database::config&)config
                             encryptionKey: (CBLSymmetricKey*)key
                                     error: (NSError**)outError;

+ (NSDictionary*) bodyOfNode: (const forestdb::Revision*)revNode;
+ (BOOL) bodyOfNode: (const forestdb::Revision*)rev into: (CBLFleeceRevDictionary*)body;

+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (forestdb::VersionedDocument&)doc
                                               revID: (NSString*)revID
                                            withBody: (BOOL)withBody;

/** Stores the body of a revision (including metadata) into a CBL_MutableRevision. */
+ (BOOL) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                              doc: (forestdb::VersionedDocument&)doc;

/** Returns the revIDs of all current leaf revisions, in descending order of priority. */
+ (NSArray*) getCurrentRevisionIDs: (forestdb::VersionedDocument&)doc
                    includeDeleted: (BOOL)includeDeleted;

/** Returns a revision & its ancestors as CBL_Revision objects, in reverse chronological order.
    If 'ancestorRevIDs' is present, the revision history will only go back as
    far as any of the revision ID strings in that array. */
+ (NSArray*) getRevisionHistoryOfNode: (const forestdb::Revision*)revNode
                         backToRevIDs: (NSSet*)ancestorRevIDs;

@end


/** Wrapper for an NSArray of Fleece data, that avoids having to parse the data if it's not used.
 NSData objects in the array will be parsed into native objects before being returned to the caller from -objectAtIndex. */
@interface CBLLazyArrayOfFleece : NSArray

/** Initialize a lazy array.
 @param array   An NSArray of NSData objects, each containing Fleece. */
- (instancetype) initWithMutableArray: (NSMutableArray*)array;
@end
