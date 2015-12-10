//
//  CBL_Body+Fleece.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Body.h"
#ifdef __cplusplus
#import "slice.hh"
#endif


@interface CBL_Body (Fleece)

#ifdef __cplusplus
+ (fleece::alloc_slice) encodeRevAsFleeceSlice: (NSDictionary*)properties;
+ (NSData*) canonicalJSONFromFleece: (fleece::slice)fleece;
#endif

+ (NSData*) encodeRevAsFleece: (NSDictionary*)properties;

+ (id) objectWithFleeceData: (NSData*)fleece;

+ (NSDictionary*) dictionaryWithFleeceData: (NSData*)fleece
                                     docID: (NSString*)docID
                                     revID: (id)revID
                                   deleted: (BOOL)deleted;

@end
