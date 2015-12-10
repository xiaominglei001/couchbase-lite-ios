//
//  CBL_Body.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Body.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLRevDictionary.h"
#import "CBL_Body+Fleece.h"


@implementation CBL_Body
{
    @private
    NSData* _json;
    NSData* _fleece;
    NSDictionary* _object;
    BOOL _error;
    NSString *_docID, *_revID;
    BOOL _deleted;
}

- (instancetype) initWithProperties: (UU NSDictionary*)properties {
    NSParameterAssert(properties);
    self = [super init];
    if (self) {
        _object = [properties copy];
    }
    return self;
}

- (instancetype) initWithArray: (NSArray*)array {
    return [self initWithProperties: (id)array];
}

- (instancetype) initWithJSON: (NSData*)json {
    self = [super init];
    if (self) {
        _json = json ? [json copy] : [[NSData alloc] init];
    }
    return self;
}

- (instancetype) initWithFleece: (NSData*)fleece {
    NSParameterAssert(fleece);
    self = [super init];
    if (self) {
        _fleece = [fleece copy];
    }
    return self;
}

+ (instancetype) bodyWithProperties: (NSDictionary*)properties {
    return [[self alloc] initWithProperties: properties];
}
+ (instancetype) bodyWithJSON: (NSData*)json {
    return [[self alloc] initWithJSON: json];
}

- (instancetype) initWithJSON: (NSData*)json
                  addingDocID: (NSString*)docID
                        revID: (NSString*)revID
                      deleted: (BOOL)deleted
{
    self = [self initWithJSON: json];
    if (self) {
        _docID = [docID copy];
        _revID = [revID copy];
        _deleted = deleted;
    }
    return self;
}

- (instancetype) initWithFleece: (NSData*)fleece
                    addingDocID: (NSString*)docID
                          revID: (NSString*)revID
                        deleted: (BOOL)deleted
{
    self = [self initWithFleece: fleece];
    if (self) {
        _docID = [docID copy];
        _revID = [revID copy];
        _deleted = deleted;
    }
    return self;
}

- (id) copyWithZone: (NSZone*)zone {
    CBL_Body* body = [[[self class] allocWithZone: zone] init];
    body->_object = [_object copy];
    body->_json = _json;
    body->_fleece = _fleece;
    body->_docID = _docID;
    body->_revID = _revID;
    body->_deleted = _deleted;
    body->_error = _error;
    return body;
}

@synthesize error=_error;

- (BOOL) isValidJSON {
    // Yes, this is just like asObject except it doesn't warn.
    if (!_object && !_error) {
        if (_fleece)
            return YES;
        _object = [[CBLJSON JSONObjectWithData: _json options: 0 error: NULL] copy];
        if (!_object) {
            _error = YES;
        }
    }
    return _object != nil;
}

- (NSData*) asJSON {
    if (_json) {
        if (_docID) {
            NSDictionary* meta = _deleted ? @{@"_id": _docID, @"_rev": _revID, @"_deleted": @YES} : @{@"_id": _docID, @"_rev": _revID};
            _json = [CBLJSON appendDictionary: meta toJSONDictionaryData: _json];
            _docID = _revID = nil;
        }
    } else if (!_error) {
        _json = [[CBLJSON dataWithJSONObject: self.asObject options: 0 error: NULL] copy];
        if (!_json) {
            Warn(@"CBL_Body: couldn't convert to JSON");
            _error = YES;
        }
    }
    return _json;
}

- (NSData*) asPrettyJSON {
    id props = self.asObject;
    if (props) {
        NSData* json = [CBLJSON dataWithJSONObject: props
                                          options: CBLJSONWritingPrettyPrinted
                                            error: NULL];
        if (json) {
            NSMutableData* mjson = [json mutableCopy];
            [mjson appendBytes: "\n" length: 1];
            return mjson;
        }
    }
    return self.asJSON;
}

- (NSString*) asJSONString {
    return self.asJSON.my_UTF8ToString;
}

- (NSData*) asFleece {
    if (_fleece)
        return _fleece;
    return [CBL_Body encodeRevAsFleece: self.asObject];
}

- (id) asObject {
    if (!_object && !_error) {
        id object;
        if (_json) {
            NSError* error = nil;
            object = [[CBLJSON JSONObjectWithData: _json options: 0 error: &error] copy];
            if (![object isKindOfClass: [NSDictionary class]]) {
                Warn(@"CBL_Body: couldn't parse JSON to dictionary: %@ (error=%@)", [_json my_UTF8ToString], error);
                _error = YES;
                return nil;
            }
            if (_docID)
                object = [[CBLRevDictionary alloc] initWithDictionary: object
                                                                docID: _docID
                                                                revID: _revID
                                                              deleted: _deleted];
        } else {
            Assert(_fleece);
            object = [CBL_Body dictionaryWithFleeceData: _fleece
                                                  docID: _docID
                                                  revID: _revID
                                                deleted: _deleted];
            if (!object)
                _error = YES;
        }
        _object = object;
    }
    return _object;
}

- (NSDictionary*) properties {
    id object = self.asObject;
    if ([object isKindOfClass: [NSDictionary class]])
        return object;
    else
        return nil;
}

- (id) objectForKeyedSubscript: (NSString*)key {
    return (self.properties)[key];
}

- (BOOL) compact {
    if (!_fleece && !_json)
        (void)[self asJSON];
    if (_error)
        return NO;
    _object = nil;
    return YES;
}

@end



@implementation NSDictionary (CBL_Body)
- (NSString*) cbl_id                {return $castIf(NSString, self[@"_id"]);}
- (NSString*) cbl_rev               {return $castIf(NSString, self[@"_rev"]);}
- (BOOL) cbl_deleted                {return $castIf(NSNumber, self[@"_deleted"]).boolValue;}
- (NSDictionary*) cbl_attachments   {return $castIf(NSDictionary, self[@"_attachments"]);}
@end


