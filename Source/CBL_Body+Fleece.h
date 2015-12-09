//
//  CBL_Body+Fleece.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Body.h"

@interface CBL_Body (Fleece)

+ (NSData*) encodeRevAsFleece: (NSDictionary*)properties;

+ (id) objectWithFleeceData: (NSData*)fleece;

@end
