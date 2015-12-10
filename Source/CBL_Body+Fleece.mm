//
//  CBL_Body+Fleece.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Body+Fleece.h"
#import "CBLFleeceRevDictionary.h"
#import "CBLInternal.h"
#import "Encoder.hh"

using namespace fleece;


@implementation CBL_Body (Fleece)


+ (alloc_slice) encodeRevAsFleeceSlice: (UU NSDictionary*)properties {
    try {
        Writer writer;
        Encoder encoder(writer);
        Encoder &encoderP = encoder;

        encoder.beginDictionary((uint32_t)properties.count);
        [properties enumerateKeysAndObjectsUsingBlock:^(__unsafe_unretained id key,
                                                        __unsafe_unretained id value, BOOL *stop) {
            nsstring_slice keyBytes(key);
            // Skip top-level metadata except for _attachments:
            if (keyBytes.size > 0 && keyBytes[0] == '_' && keyBytes != slice("_attachments"))
                return;
            encoderP.writeKey(keyBytes);
            encoderP.write(value);
        }];
        encoder.endDictionary();

        encoder.end();
        return writer.extractOutput();
    } catch (const char *msg) {
        Warn(@"Can't encode document body: %s", msg);
    } catch (...) {
        Warn(@"Can't encode document body (unexpected exception)");
    }
    return alloc_slice();
}

+ (NSData*) encodeRevAsFleece: (UU NSDictionary*)properties {
    return [self encodeRevAsFleeceSlice: properties].convertToNSData();
}


+ (NSData*) canonicalJSONFromFleece: (slice)fleece {
    auto root = value::fromTrustedData(fleece);
    return root->toJSON().convertToNSData();
}


+ (id) objectWithFleeceData: (UU NSData*)fleece {
    if (!fleece)
        return nil;
    id obj = [CBLFleeceRevDictionary objectWithFleeceData: fleece trusted: YES];
    if (!obj)
        Warn(@"Couldn't parse Fleece data %@", fleece);
    return obj;
}


+ (NSDictionary*) dictionaryWithFleeceData: (UU NSData*)fleece
                                     docID: (UU NSString*)docID
                                     revID: (UU id)revID
                                   deleted: (BOOL)deleted
{
    return [[CBLFleeceRevDictionary alloc] initWithFleeceData: fleece
                                                      trusted: YES
                                                        docID: docID
                                                        revID: revID
                                                      deleted: deleted];
}


@end
