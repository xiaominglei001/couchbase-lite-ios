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




@implementation CBIndexedJSONEncoder
{
    NSUInteger _headerLength;
    NSUInteger _curEntry;
    size_t _lastOffset;
}


- (BOOL) encode: (id)object {
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
    header->magic = EndianU16_NtoB(kDictMagicNumber);
    header->count = EndianU16_NtoB(count);
    _curEntry = 0;

    return [super encode: object];
}


- (BOOL) encodeKey:(id)key value:(id)value {
    // Fill in the header entry with the key's hash and the offset in the JSON:
    NSMutableData* encoded = self.output;
    DictHeader *header = encoded.mutableBytes;
    size_t offset = encoded.length - _headerLength;
    if (_curEntry > 0)
        ++offset; // skip comma
    DictEntry *entry = &header->entry[_curEntry++];
    entry->hash = EndianU16_NtoB([[self class] indexHash: key]);
    size_t relOffset = offset - _lastOffset;
    if (relOffset > 0xFFFF)
        return NO; // Can't represent in indexed form
    entry->offset = EndianU16_NtoB(relOffset);
    _lastOffset = offset;
    // Finally append the JSON key and value to the output:
    return [super encodeKey: key value: value];
}


+ (UInt16) indexHash: (NSString*)key {
    __block uint32_t output = 0;
    CBWithStringBytes(key, ^(const char *bytes, size_t len) {
        MurmurHash3_x86_32(bytes, (int)len, 0/*seed*/, &output);
    });
    return output & 0xFFFF;
}


+ (BOOL) isValidIndexedJSON: (NSData*)data {
    const DictHeader* header = (const DictHeader*)data.bytes;
    if (data.length < sizeof(DictHeader) || EndianU16_BtoN(header->magic) != kDictMagicNumber)
        return NO;
    NSUInteger count = EndianU16_BtoN(header->count);
    const uint8_t* jsonStart = (const uint8_t*)&header->entry[count];
    size_t headerSize = jsonStart - (const uint8_t*)header;
    if (data.length < headerSize + 2)
        return NO;
    size_t curOffset = 0;
    for (NSUInteger i = 0; i < count; i++)
        curOffset += EndianU16_BtoN(header->entry[i].offset);
    if (curOffset > data.length - headerSize - 2)
        return NO;
    return YES;
}

@end
