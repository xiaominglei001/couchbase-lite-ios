//
//  CBLRemoteQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/5/14.
//
//

#import <CouchbaseLite/CouchbaseLite.h>

@interface CBLRemoteQuery : CBLQuery

- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remoteDB
                             view: (NSString*)viewName;

@property CBLReplication* puller;

@end
