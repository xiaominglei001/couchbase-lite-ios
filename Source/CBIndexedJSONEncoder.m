//
//  CBIndexedJSONEncoder.m
//  CBJSON
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "CBIndexedJSONEncoder.h"
#import "CBIndexedJSONFormat.h"
#include "murmurhash3_x86_32.h"


#define UU __unsafe_unretained


@implementation CBIndexedJSONEncoder
{
    NSUInteger _headerLength;
    NSUInteger _curEntry;
    size_t _lastOffset;
    unsigned _nesting;
}


- (BOOL) encode: (UU id)object {
    if (![object isKindOfClass: [NSDictionary class]])
        return NO;

    NSDictionary* dict = object;
    NSUInteger count = dict.count;
    if (count > 0xFFFF)
        return NO;
    _headerLength = 4 + 4*count;

    NSMutableData* encoded = self.output;
    [encoded setLength: _headerLength];
    DictHeader *header = encoded.mutableBytes;
    header->magic = NSSwapHostShortToBig(kDictMagicNumber);
    header->count = NSSwapHostShortToBig((uint16_t)count);
    _curEntry = 0;

    return [super encode: object];
}


- (BOOL) encodeKey:(UU id)key value:(UU id)value {
    if (_nesting == 0) {
        // Fill in the header entry with the key's hash and the offset in the JSON:
        NSMutableData* encoded = self.output;
        DictHeader *header = encoded.mutableBytes;
        size_t offset = encoded.length - _headerLength;
        if (_curEntry > 0)
            ++offset; // skip comma
        DictEntry *entry = &header->entry[_curEntry++];
        entry->hash = NSSwapHostShortToBig(indexHash(key));
        size_t relOffset = offset - _lastOffset;
        if (relOffset > 0xFFFF)
            return NO; // Can't represent in indexed form
        entry->offset = NSSwapHostShortToBig((uint16_t)relOffset);
        _lastOffset = offset;
    }

    // Finally append the JSON key and value to the output:
    ++_nesting;
    BOOL result = [super encodeKey: key value: value];
    --_nesting;
    return result;
}


static UInt16 indexHash(UU NSString* key) {
    __block UInt16 output = 0;
    CBWithStringBytes(key, ^(const char *bytes, size_t len) {
        output = CBJSONKeyHash(bytes, len);
    });
    return output;
}


+ (BOOL) mayBeIndexedJSON: (UU NSData*)data {
    const DictHeader* header = (const DictHeader*)data.bytes;
    return data.length >= sizeof(DictHeader) && NSSwapBigShortToHost(header->magic) == kDictMagicNumber;
}


+ (BOOL) isValidIndexedJSON: (UU NSData*)data {
    const size_t length = data.length;
    const DictHeader* header = (const DictHeader*)data.bytes;
    if (length < sizeof(DictHeader) || NSSwapBigShortToHost(header->magic) != kDictMagicNumber)
        return NO;
    NSUInteger count = NSSwapBigShortToHost(header->count);
    const uint8_t* jsonStart = (const uint8_t*)&header->entry[count];
    size_t headerSize = jsonStart - (const uint8_t*)header;
    if (length < headerSize + 2)
        return NO;
    size_t curOffset = 0;
    for (NSUInteger i = 0; i < count; i++)
        curOffset += NSSwapBigShortToHost(header->entry[i].offset);
    if (curOffset > length - headerSize - 2)
        return NO;
    return YES;
}


+ (NSData*) removeIndex: (UU NSData*)data {
    if (![self mayBeIndexedJSON: data])
        return data;
    const DictHeader* header = (const DictHeader*)data.bytes;
    NSUInteger count = NSSwapBigShortToHost(header->count);
    const uint8_t* jsonStart = (const uint8_t*)&header->entry[count];
    NSUInteger indexLength = jsonStart - (const uint8_t*)header;
    size_t dataLength = data.length;
    if (indexLength > dataLength)
        return data;
    return [data subdataWithRange: NSMakeRange(indexLength, dataLength-indexLength)];
}


@end
