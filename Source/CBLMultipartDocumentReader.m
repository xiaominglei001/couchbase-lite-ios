//
//  CBLMultipartDocumentReader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMultipartDocumentReader.h"
#import "CBLDatabase+Attachments.h"
#import "CBL_BlobStore.h"
#import "CBL_Attachment.h"
#import "CBLInternal.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CollectionUtils.h"
#import "MYStreamUtils.h"
#import "GTMNSData+zlib.h"
#import "ZDCodec.h"


static int compressionPercent(uint64_t from, uint64_t to) {
    return (int)( ((double)to - (double)from) / (double)to * 100.0 );
}


@interface CBLMultipartDocumentReader () <CBLMultipartReaderDelegate, NSStreamDelegate>
@end


@implementation CBLMultipartDocumentReader
{
@private
    CBLDatabase* _database;
    NSString* _docID;
    CBLStatus _status;
    CBLMultipartReader* _multipartReader;
    NSMutableData* _jsonBuffer;
    BOOL _jsonCompressed;
    ZDCodec* _jsonDecoder;                        // Decodes delta-compressed JSON
    NSUInteger _partRawSize;
    CBL_BlobStoreWriter* _curAttachment;
    NSMutableDictionary* _attachmentsByName;      // maps attachment name --> CBL_BlobStoreWriter
    NSMutableDictionary* _attachmentsByDigest;    // maps attachment MD5 --> CBL_BlobStoreWriter
    NSMutableDictionary* _document;
    CBLMultipartDocumentReaderCompletionBlock _completionBlock;
    __strong id _retainSelf; // Used to keep this object alive by keeping a reference to self
}


+ (NSDictionary*) readData: (NSData*)data
                   headers: (NSDictionary*)headers
                toDatabase: (CBLDatabase*)database
                     docID: (NSString*)docID
                    status: (CBLStatus*)outStatus
{
    if (data.length == 0) {
        *outStatus = kCBLStatusBadJSON;
        return nil;
    }
    NSDictionary* result = nil;
    CBLMultipartDocumentReader* reader = [[self alloc] initWithDatabase: database docID: docID];
    if ([reader setHeaders: headers]
            && [reader appendData: data]
            && [reader finish]) {
        result = reader.document;
    }
    if (outStatus)
        *outStatus = reader.status;
    return result;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                            docID: (NSString*)docID
{
    Assert(database);
    self = [super init];
    if (self) {
        _database = database;
        _docID = docID;
    }
    return self;
}


- (void) dealloc {
    [_curAttachment cancel];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[_id=\"%@\"]",
            self.class, (_docID ?: _document.cbl_id)];
}



@synthesize status=_status, document=_document;


- (NSUInteger) attachmentCount {
    return _attachmentsByDigest.count;
}


- (BOOL) setHeaders: (NSDictionary*)headers {
    NSString* contentType = headers[@"Content-Type"];
    if ([contentType hasPrefix: @"multipart/"]) {
        // Multipart, so initialize the parser:
        LogTo(SyncVerbose, @"%@: has attachments, %@", self, contentType);
        _multipartReader = [[CBLMultipartReader alloc] initWithContentType: contentType delegate: self];
        if (_multipartReader) {
            _attachmentsByName = [[NSMutableDictionary alloc] init];
            _attachmentsByDigest = [[NSMutableDictionary alloc] init];
            return YES;
        }
    } else if (contentType == nil || [contentType hasPrefix: @"application/json"]
                                  || [contentType hasPrefix: @"text/plain"]) {
        // No multipart, so no attachments. Body is pure JSON. (We allow text/plain because CouchDB
        // sends JSON responses using the wrong content-type.)
        return [self startJSONBufferWithHeaders: headers];
    }
    // Unknown/invalid MIME type:
    _status = kCBLStatusNotAcceptable;
    return NO;
}


- (BOOL) appendData:(NSData *)data {
    if (_multipartReader) {
        [_multipartReader appendData: data];
        if (_multipartReader.error) {
            Warn(@"%@: received unparseable MIME multipart response: %@",
                 self, _multipartReader.error);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    } else {
        [_jsonBuffer appendData: data];
    }
    return YES;
}


- (BOOL) finish {
    LogTo(SyncVerbose, @"%@: Finished loading (%u attachments)",
          self, (unsigned)_attachmentsByDigest.count);
    if (_multipartReader) {
        if (!_multipartReader.finished) {
            Warn(@"%@: received incomplete MIME multipart response", self);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
        
        if (![self registerAttachments]) {
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    } else {
        if (![self parseJSONBuffer])
            return NO;
    }
    _status = kCBLStatusCreated;
    return YES;
}


#pragma mark - ASYNCHRONOUS MODE:


+ (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
              toDatabase: (CBLDatabase*)database
                   docID: (NSString*)docID
                    then: (CBLMultipartDocumentReaderCompletionBlock)onCompletion
{
    CBLMultipartDocumentReader* reader = [[self alloc] initWithDatabase: database docID: docID];
    return [reader readStream: stream headers: headers then: onCompletion];
}


- (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
                    then: (CBLMultipartDocumentReaderCompletionBlock)completionBlock
{
    if ([self setHeaders: headers]) {
        LogTo(SyncVerbose, @"%@: Reading from input stream...", self);
        _retainSelf = self;  // balanced by release in -finishAsync:
        _completionBlock = [completionBlock copy];
        [stream open];
        stream.delegate = self;
        [stream scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    }
    return _status;
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    BOOL finish = NO;
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable:
            finish = ![self readFromStream: (NSInputStream*)stream];
            break;
        case NSStreamEventEndEncountered:
            finish = YES;
            break;
        case NSStreamEventErrorOccurred:
            Warn(@"%@: error reading from stream: %@", self, stream.streamError);
            _status = kCBLStatusUpstreamError;
            finish = YES;
            break;
        default:
            break;
    }
    if (finish)
        [self finishAsync: (NSInputStream*)stream];
}


- (BOOL) readFromStream: (NSInputStream*)stream {
    BOOL readOK = [stream my_readData: ^(NSData *data) {
        [self appendData: data];
    }];
    if (!readOK) {
        Warn(@"%@: error reading from stream: %@", self, stream.streamError);
        _status = kCBLStatusUpstreamError;
    }
    return !CBLStatusIsError(_status);
}


- (void) finishAsync: (NSInputStream*)stream {
    stream.delegate = nil;
    [stream close];
    if (!CBLStatusIsError(_status))
        [self finish];
    _completionBlock(self);
    _completionBlock = nil;
    _retainSelf = nil;  // clears the reference acquired in -readStream:
}


#pragma mark - MIME PARSER CALLBACKS:


/** Callback: A part's headers have been parsed, but not yet its data. */
- (BOOL) startedPart: (NSDictionary*)headers {
    // First MIME part is the document's JSON body; the rest are attachments.
    _partRawSize = 0;
    if (!_document) {
        return [self startJSONBufferWithHeaders: headers];
    } else {
        _curAttachment = [_database attachmentWriter];
        
        // See whether the attachment name is in the headers.
        NSString* name = nil, *deltaSrc = nil;
        NSString* disposition = headers[@"Content-Disposition"];
        if ([disposition hasPrefix: @"attachment; filename="]) {
            // TODO: Parse this less simplistically. Right now it assumes it's in exactly the same
            // format generated by -[CBL_Pusher uploadMultipartRevision:]. CouchDB (as of 1.2) doesn't
            // output any headers at all on attachments so there's no compatibility issue yet.
            name = CBLUnquoteString([disposition substringFromIndex: 21]);
            if (name) {
                _attachmentsByName[name] = _curAttachment;
                // Is this attachment delta-encoded?
                NSDictionary* metadata = _document.cbl_attachments[name];
                if ([metadata[@"encoding"] isEqual: @"zdelta"]) {
                    deltaSrc = $castIf(NSString, metadata[@"deltasrc"]);
                    CBLBlobKey key;
                    if (![CBL_Attachment digest: deltaSrc toBlobKey: &key]) {
                        Warn(@"Attachment JSON has invalid deltaSrc: '%@'", deltaSrc);
                        return NO;
                    } else if (![_curAttachment decodeZDeltaFrom: key]) {
                        Warn(@"Attachment deltaSrc is unknown attachment '%@'", deltaSrc);
                        return NO;
                    }
                    [(NSMutableDictionary*)metadata removeObjectForKey: @"encoding"];
                    [(NSMutableDictionary*)metadata removeObjectForKey: @"deltasrc"];
                }
            }
        }
        LogTo(SyncVerbose, @"%@: Starting attachment #%u \"%@\", deltaSrc=%@",
              self, (unsigned)_attachmentsByDigest.count + 1, name, deltaSrc);
        return YES;
    }
}


/** Callback: Append data to a MIME part's body. */
- (BOOL) appendToPart: (NSData*)data {
    _partRawSize += data.length;
    if (_jsonBuffer)
        return [self appendToJSONBuffer: data];
    else {
        [_curAttachment appendData: data];
        return YES;
    }
}


/** Callback: A MIME part is complete. */
- (BOOL) finishedPart {
    if (_jsonBuffer) {
        return [self parseJSONBuffer];
    } else {
        // Finished downloading an attachment. Remember the association from the MD5 digest
        // (which appears in the body's _attachments dict) to the blob-store key of the data.
        [_curAttachment finish];
        NSString* md5Str = _curAttachment.MD5DigestString;
#ifndef MY_DISABLE_LOGGING
        if (WillLogTo(SyncVerbose)) {
            CBLBlobKey key = _curAttachment.blobKey;
            NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
            LogTo(SyncVerbose, @"%@: Finished attachment #%u: len=%uk, %d%% compression, digest=%@, SHA1=%@",
                  self, (unsigned)_attachmentsByDigest.count+1,
                  (unsigned)_curAttachment.length/1024,
                  compressionPercent(_partRawSize, _curAttachment.length),
                  md5Str, keyData);
        }
#endif
        _attachmentsByDigest[md5Str] = _curAttachment;
        _curAttachment = nil;
        return YES;
    }
}


#pragma mark - JSON PARSING:


- (BOOL) startJSONBufferWithHeaders: (NSDictionary*)headers {
    _jsonBuffer = [[NSMutableData alloc] initWithCapacity: 1024];
    NSString* contentEncoding = headers[@"Content-Encoding"];
    if ([contentEncoding isEqualToString: @"zdelta"]) {
        NSString* sourceRevID = headers[@"X-Delta-Source"];
        if (_docID == nil || sourceRevID == nil) {
            Warn(@"%@: Can't interpret delta, docID/revID not known", self);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
        CBLStatus status = 0;
        CBL_Revision* rev = [_database getDocumentWithID: _docID revisionID: sourceRevID
                                                 options: kCBLNoIDs status: &status];
        NSData* sourceJSON = rev.body.asJSON;
        if (!sourceJSON) {
            Warn(@"%@: Can't interpret delta, can't get source JSON {%@ #%@} (status=%d)",
                 self, _docID, sourceRevID, status);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
        _jsonDecoder = [[ZDCodec alloc] initWithSource: sourceJSON compressing: NO];
    } else {
        _jsonCompressed = [contentEncoding isEqualToString: @"gzip"];
    }
    return YES;
}


- (BOOL) appendToJSONBuffer: (NSData*)data {
    if (_jsonDecoder) {
        NSMutableData* jsonBuffer = _jsonBuffer;
        BOOL ok = [_jsonDecoder addBytes: data.bytes length: data.length
                                onOutput: ^(const void *bytes, size_t length) {
                                    [jsonBuffer appendBytes: bytes length: length];
                                }];
        if (!ok) {
            Warn(@"%@: ZDelta decoder error %d", self, _jsonDecoder.status);
            _status = kCBLStatusUpstreamError;
        }
        return ok;
    } else {
        [_jsonBuffer appendData: data];
        return YES;
    }
}


- (BOOL) parseJSONBuffer {
    if (_jsonDecoder) {
        if (![self appendToJSONBuffer: nil]) // flush decoder
            return NO;
        _jsonDecoder = nil;
    }
    NSData* json = _jsonBuffer;
    _jsonBuffer = nil;
    if (_jsonCompressed) {
        json = [NSData gtm_dataByInflatingData: json];
        if (!json) {
            Warn(@"%@: received corrupt gzip-encoded JSON part", self);
            _status = kCBLStatusUpstreamError;
            return NO;
        }
    }
    LogTo(SyncVerbose, @"%@: Received JSON body, %u bytes (%d%% compression)",
          self, (unsigned)json.length, compressionPercent(_partRawSize, json.length));
    id document = [CBLJSON JSONObjectWithData: json
                                       options: CBLJSONReadingMutableContainers
                                         error: NULL];
    if (![document isKindOfClass: [NSDictionary class]]) {
        Warn(@"%@: received unparseable JSON data '%@'",
             self, ([json my_UTF8ToString] ?: json));
        _status = kCBLStatusUpstreamError;
        return NO;
    }
    _document = document;
    return YES;
}


#pragma mark - FINISHING UP:


- (BOOL) registerAttachments {
    NSDictionary* attachments = _document.cbl_attachments;
    if (attachments && ![attachments isKindOfClass: [NSDictionary class]]) {
        Warn(@"%@: _attachments property is not a dictionary", self);
        return NO;
    }
    NSUInteger nAttachmentsInDoc = 0;
    for (NSString* attachmentName in attachments) {
        NSMutableDictionary* attachment = attachments[attachmentName];

        // Get the length:
        NSNumber* lengthObj = attachment[@"encoded_length"] ?: attachment[@"length"];
        if (![lengthObj isKindOfClass: [NSNumber class]]) {
            Warn(@"%@: Attachment '%@' has invalid length property %@",
                 self, attachmentName, lengthObj);
            return NO;
        }
        UInt64 length = lengthObj.unsignedLongLongValue;

        if ([attachment[@"follows"] isEqual: $true]) {
            // Check that each attachment in the JSON corresponds to an attachment MIME body.
            // Look up the attachment by either its MIME Content-Disposition header or MD5 digest:
            NSString* digest = attachment[@"digest"];
            CBL_BlobStoreWriter* writer = _attachmentsByName[attachmentName];
            if (writer) {
                // Identified the MIME body by the filename in its Disposition header:
                NSString* actualMD5Digest = writer.MD5DigestString;
                NSString* actualSHADigest = writer.SHA1DigestString;
                if (digest && !$equal(digest, actualMD5Digest) && !$equal(digest, actualSHADigest)) {
                    Warn(@"%@: Attachment '%@' has incorrect digest property (%@; should be %@ or %@)",
                         self, attachmentName, digest, actualMD5Digest, actualSHADigest);
                    return NO;
                }
                attachment[@"digest"] = actualMD5Digest;
            } else if (digest) {
                // Else look up the MIME body by its computed digest:
                writer = _attachmentsByDigest[digest];
                if (!writer) {
                    Warn(@"%@: Attachment '%@' does not appear in a MIME body",
                         self, attachmentName);
                    return NO;
                }
            } else if (attachments.count == 1 && _attachmentsByDigest.count == 1) {
                // Else there's only one attachment, so just assume it matches & use it:
                writer = [_attachmentsByDigest allValues][0];
                attachment[@"digest"] = writer.MD5DigestString;
            } else {
                // No digest metatata, no filename in MIME body; give up:
                Warn(@"%@: Attachment '%@' has no digest metadata; cannot identify MIME body",
                     self, attachmentName);
                return NO;
            }
            
            // Check that the length matches:
            if (writer.length != length) {
                Warn(@"%@: Attachment '%@' has incorrect length field %@ (should be %llu)",
                    self, attachmentName, lengthObj, writer.length);
                return NO;
            }
            
            ++nAttachmentsInDoc;
        } else if (attachment[@"data"] != nil && length > 1000) {
            // This isn't harmful but it's quite inefficient of the server
            Warn(@"%@: Attachment '%@' sent inline (length=%llu)", self, attachmentName, length);
        }
    }
    if (nAttachmentsInDoc < _attachmentsByDigest.count) {
        Warn(@"%@: More MIME bodies (%u) than attachments (%u)",
            self, (unsigned)_attachmentsByDigest.count, (unsigned)nAttachmentsInDoc);
        return NO;
    }
    
    // If everything's copacetic, hand over the (uninstalled) blobs to the database to remember:
    [_database rememberAttachmentWritersForDigests: _attachmentsByDigest];
    return YES;
}


@end
