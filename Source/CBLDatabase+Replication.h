//
//  CBLDatabase+Replication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
@class CBL_Replicator;


@interface CBLDatabase (Replication)

@property (readonly) NSArray* activeReplicators;

- (CBL_Replicator*) activeReplicatorLike: (CBL_Replicator*)repl;

- (void) addActiveReplicator: (CBL_Replicator*)repl;

/** Removes from `revs` all the revisions that already exist in this database. */
- (BOOL) findMissingRevisions: (CBL_RevisionList*)revs;

/** Removes from `revs` all the revisions whose document doesn't exist in this database. */
- (BOOL) findExistingDocs: (CBL_RevisionList*)revs;

@end
