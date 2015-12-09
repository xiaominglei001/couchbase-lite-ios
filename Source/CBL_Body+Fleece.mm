//
//  CBL_Body+Fleece.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Body+Fleece.h"
#import "FleeceDocument.h"
#import "CBLInternal.h"
#import "Encoder.hh"


@implementation CBL_Body (Fleece)


+ (NSData*) encodeRevAsFleece: (NSDictionary*)properties {
    fleece::Writer writer;
    fleece::Encoder encoder(writer);

    encoder.beginDictionary((uint32_t)properties.count);
    for (NSString* key in properties) {
        if ([key hasPrefix: @"_"] && ![key isEqualToString: @"_attachments"])
            continue;
        fleece::nsstring_slice slice(key);
        encoder.writeKey(slice);
        encoder.write(properties[key]);
    }
    encoder.endDictionary();

    encoder.end();
    return writer.extractOutput().convertToNSData();
}


+ (id) objectWithFleeceData: (UU NSData*)fleece {
    if (!fleece)
        return nil;
    id obj = [FleeceDocument objectWithFleeceData: fleece trusted: YES];
    if (!obj)
        Warn(@"Couldn't parse Fleece data %@", fleece);
    return obj;
}


@end
