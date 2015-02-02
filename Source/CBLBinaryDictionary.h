//
//  CBLBinary.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/15.
//
//

#import <Foundation/Foundation.h>


@interface CBLBinaryDictionary : NSDictionary

+ (BOOL) isValidBinary: (NSData*)binary;
+ (NSData*) JSONToBinary: (NSData*)json;
+ (NSData*) binaryToJSON: (NSData*)binary;
+ (NSData*) objectToBinary: (id)object;

- (instancetype) initWithBinary: (NSData*)binary
                   addingValues: (NSMutableDictionary*)dictToAdd
                    cacheValues: (BOOL)cacheValues;

@property (readonly, nonatomic) NSData* binaryData;

- (BOOL)containsValueForKey: (NSString*)key;

@end
