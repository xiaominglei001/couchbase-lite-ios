//
//  CBIndexedJSONTests.m
//  CBJSONTests
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "Test.h"
#import "CBIndexedJSONEncoder.h"
#import "CBIndexedJSONDict.h"
#import "CBIndexedJSONFormat.h"


static NSDictionary* sampleDict(void) {
    return @{@"num": @(1234),
             @"string": @"String value!",
             @"": [NSNull null]};
}

// Returns some sample encoded data
static NSData* sampleEncodedData(void) {
    CBIndexedJSONEncoder* encoder = [[CBIndexedJSONEncoder alloc] init];
    Assert([encoder encode: sampleDict()], @"encode failed");
    return encoder.encodedData;
}

TestCase(CBIndexedJSON_Format) {
    AssertEq(sizeof(DictEntry), (size_t)4);
    AssertEq(sizeof(DictHeader), (size_t)4);
    AssertEq(offsetof(DictHeader,entry[2].hash), (size_t)12);
}

TestCase(CBIndexedJSON_IndexedEncoder) {
    NSDictionary* dict = sampleDict();
    NSData* encoded = sampleEncodedData();
    NSLog(@"Encoded: %@", encoded);

    const DictHeader* h = encoded.bytes;
    AssertEq(NSSwapBigShortToHost(h->count),            (UInt16)dict.count);
    AssertEq(NSSwapBigShortToHost(h->magic),            (UInt16)kDictMagicNumber);
    AssertEq(NSSwapBigShortToHost(h->entry[0].hash),    (UInt16)32896);
    AssertEq(NSSwapBigShortToHost(h->entry[0].offset),  (UInt16)1);
    AssertEq(NSSwapBigShortToHost(h->entry[1].hash),    (UInt16)31403);
    AssertEq(NSSwapBigShortToHost(h->entry[1].offset),  (UInt16)11);
    AssertEq(NSSwapBigShortToHost(h->entry[2].hash),    (UInt16)0);
    AssertEq(NSSwapBigShortToHost(h->entry[2].offset),  (UInt16)25);

    // Make sure each entry offset points to a '"' character:
    const char* json = (const char*)&h->entry[dict.count];
    for (NSUInteger i=0; i<dict.count; i++) {
        json += NSSwapBigShortToHost(h->entry[i].offset);
        AssertEq(*json, (char)'"'/*, @"Entry #%d", i*/);
    }

    Assert([CBIndexedJSONEncoder isValidIndexedJSON: encoded]);
}

TestCase(CBIndexedJSON_IndexedDict) {
    NSDictionary* dict = sampleDict();
    NSData* encoded = sampleEncodedData();

    CBIndexedJSONDict* parsed = [[CBIndexedJSONDict alloc] initWithData: encoded
                                                           addingValues: nil
                                                            cacheValues: NO];
    Assert(parsed != nil);
    Assert([parsed isKindOfClass: [CBIndexedJSONDict class]]);
    AssertEq(parsed.count, (size_t)3);
    AssertEqual(parsed[@"num"], @1234);
    AssertEqual(parsed[@"Num"], nil);
    AssertEqual(parsed[@"string"], dict[@"string"]);
    AssertEqual(parsed[@""], dict[@""]);

    Assert([parsed containsValueForKey: @"num"]);
    Assert([parsed containsValueForKey: @""]);
    Assert(![parsed containsValueForKey: @"*"]);

    // Test key enumerator:
    NSEnumerator* e = parsed.keyEnumerator;
    Assert(e != nil);
    AssertEqual(e.nextObject, @"num");
    AssertEqual(e.nextObject, @"string");
    AssertEqual(e.nextObject, @"");

    // Test fast-enumeration:
    NSMutableSet* keys = [NSMutableSet set];
    for (NSString* key in parsed) {
        [keys addObject: key];
    }
    AssertEqual(keys, [NSSet setWithArray: dict.allKeys]);

    NSDictionary* copied = [parsed copy];
    AssertEqual(copied, parsed);
    NSLog(@"Original = %@ %@", parsed.class, parsed);
    NSLog(@"Copy = %@ %@", copied.class, copied);
}

TestCase(CBIndexedJSON_AddingValues) {
    NSDictionary* dict = sampleDict();
    NSData* encoded = sampleEncodedData();

    NSMutableDictionary* added = [@{@"_id": @"foo", @"num": @4321} mutableCopy];
    CBIndexedJSONDict* parsed = [[CBIndexedJSONDict alloc] initWithData: encoded
                                                           addingValues: added
                                                            cacheValues: NO];
    AssertEq(parsed.count, (size_t)4);
    AssertEqual(parsed[@"num"], @4321); // overridden by added dict
    AssertEqual(parsed[@"Num"], nil);
    AssertEqual(parsed[@"string"], dict[@"string"]);
    AssertEqual(parsed[@""], dict[@""]);
    AssertEqual(parsed[@"_id"], @"foo");

    Assert([parsed containsValueForKey: @"_id"]);
    Assert([parsed containsValueForKey: @"num"]);

    AssertEqual(([NSSet setWithArray: parsed.allKeys]),
                          ([NSSet setWithObjects: @"_id", @"num", @"string", @"", nil]));
}

static NSTimeInterval benchmark(void (^block)()) {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    @autoreleasepool {
        block();
    }
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - start;
    return elapsed;
}

TestCase(CBIndexedJSON_Beers) {
    NSString* dir = @"/opt/couchbase/samples/beer-sample/docs"; //TEMP
    NSMutableArray* jsonDocs = [NSMutableArray array];
    NSMutableArray* indexedJsonDocs = [NSMutableArray array];
    for (NSString* filename in [[NSFileManager defaultManager] enumeratorAtPath: dir]) {
        NSString* path = [dir stringByAppendingPathComponent: filename];
        NSData* jsonData = [NSData dataWithContentsOfFile: path];
        [jsonDocs addObject: jsonData];

        NSDictionary* body = [NSJSONSerialization JSONObjectWithData: jsonData
                                                             options: 0 error: NULL];
        NSData* indexedData = [CBIndexedJSONEncoder encode: body error: NULL];
        [indexedJsonDocs addObject: indexedData];
    }
    NSLog(@"Read %u beer docs", (unsigned)indexedJsonDocs.count);

    __block UInt64 totalZip = 0;
    NSTimeInterval jsonTime = benchmark(^{
        for (NSData* jsonData in jsonDocs) {
            NSDictionary* userProps = [NSJSONSerialization JSONObjectWithData: jsonData
                                                                      options: 0 error: NULL];
            NSMutableDictionary* props = [userProps mutableCopy];
            props[@"_id"] = @"some_doc_id";
            props[@"_rev"] = @"12-deadbeefdeadbeefdeadbeefdeadbeef";
            props[@"_localseq"] = @1234;

            NSString* zip = props[@"code"];
            __unused NSString* name = props[@"name"];
            __unused NSString* city = props[@"city"];
            __unused NSString* address = props[@"address"];
            totalZip += [zip integerValue];
        }
    });
    NSLog(@"%1.10f sec for NSJSONSerialization", jsonTime);

    __block UInt64 indexedTotalZip = 0;
    NSTimeInterval indexedTime = benchmark(^{
        for (NSData* jsonData in indexedJsonDocs) {
            NSDictionary* extra = @{@"_id": @"some_doc_id",
                                    @"_rev": @"12-deadbeefdeadbeefdeadbeefdeadbeef",
                                    @"_localseq": @1234};
            NSDictionary* props = [[CBIndexedJSONDict alloc] initWithData: jsonData
                                                             addingValues: [extra mutableCopy]
                                                              cacheValues: NO];
            NSString* zip = props[@"code"];
            __unused NSString* name = props[@"name"];
            __unused NSString* city = props[@"city"];
            __unused NSString* address = props[@"address"];
            indexedTotalZip += [zip integerValue];
        }
    });
    NSLog(@"%1.10f sec for indexed JSON", indexedTime);
    AssertEq(indexedTotalZip, totalZip);
    NSLog(@"Speedup = %.2fx", jsonTime/indexedTime);
}

TestCase(CBIndexedJSON) {
    RequireTestCase(CBIndexedJSON_Format);
    RequireTestCase(CBIndexedJSON_IndexedEncoder);
    RequireTestCase(CBIndexedJSON_IndexedDict);
    RequireTestCase(CBIndexedJSON_AddingValues);
    RequireTestCase(CBIndexedJSON_Beers);
}