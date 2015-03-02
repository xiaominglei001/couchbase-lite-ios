//
//  CBL_BlobStoreWriter.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/2/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_BlobStoreWriter.h"
#import "CBLSymmetricKey.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CBLGZip.h"
#import "ZDCodec.h"
#ifdef GNUSTEP
#import <openssl/md5.h>
#endif


// Declare ZDCodec as being compliant with CBLCodec protocol (it implements the required methods)
@interface ZDCodec () <CBLCodec>
@end


@interface CBL_BlobStore (Internal)
- (NSString*) rawPathForKey: (CBLBlobKey)key;
- (NSString*) tempDir;
@end


typedef struct {
    uint8_t bytes[MD5_DIGEST_LENGTH];
} CBLMD5Key;


@implementation CBL_BlobStoreWriter
{
    @private
    CBL_BlobStore*  _store;         // The BlobStore I add my attachment to
    NSString*       _tempPath;      // Location data is written to before download is complete
    NSFileHandle*   _out;           // File handle that writes to _tempPath
    UInt64          _length;        // Current (decoded) data length
    SHA_CTX         _shaCtx;        // Computes SHA-1 digest of data so far
    MD5_CTX         _md5Ctx;        // Computes MD5 digest of data so far
    CBLBlobKey      _blobKey;       // Blob key (SHA-1 digest) of final attachment when complete
    CBLMD5Key       _MD5Digest;     // Running MD5 digest of data read so far
    id<CBLCodec>    _decompressor;  // Decompresses gzip or deltas coming in from replicator
    CBLCryptorBlock _encryptor;     // Encrypts data on its way to disk
}
@synthesize length=_length, blobKey=_blobKey;

- (instancetype) initWithStore: (CBL_BlobStore*)store {
    self = [super init];
    if (self) {
        _store = store;
        SHA1_Init(&_shaCtx);
        MD5_Init(&_md5Ctx);
                
        // Open a temporary file in the store's temporary directory: 
        NSString* filename = [CBLCreateUUID() stringByAppendingPathExtension: @"blobtmp"];
        _tempPath = [[_store.tempDir stringByAppendingPathComponent: filename] copy];
        if (!_tempPath) {
            return nil;
        }
        if (![[NSFileManager defaultManager] createFileAtPath: _tempPath
                                                     contents: nil
                                                   attributes: nil]) {
            return nil;
        }
        _out = [NSFileHandle fileHandleForWritingAtPath: _tempPath];
        if (!_out) {
            return nil;
        }
        CBLSymmetricKey* encryptionKey = _store.encryptionKey;
        if (encryptionKey)
            _encryptor = [encryptionKey createEncryptor];
    }
    return self;
}

- (BOOL) decodeZDeltaFrom: (CBLBlobKey)sourceKey {
    // Get source attachment data:
    NSData* source = [_store blobForKey: sourceKey];
    if (!source)
        return NO;
    Assert(!_decompressor);
    _decompressor = [[ZDCodec alloc] initWithSource: source compressing: NO];
    return (_decompressor != nil);
}

- (void) decodeGZip {
    Assert(!_decompressor);
    _decompressor = [[CBLGZip alloc] initForCompressing: NO];
}

- (void) appendDecodedData: (NSData*)data {
    NSUInteger dataLen = data.length;
    _length += dataLen;
    SHA1_Update(&_shaCtx, data.bytes, dataLen);
    MD5_Update(&_md5Ctx, data.bytes, dataLen);

    if (_encryptor)
        data = _encryptor(data);
    [_out writeData: data];
}

- (BOOL) appendData: (NSData*)data {
    if (_decompressor) {
        __unsafe_unretained CBL_BlobStoreWriter* slef = self;  // avoids bogus warning
        BOOL ok = [_decompressor addBytes: data.bytes length: data.length
                                onOutput: ^(const void *bytes, size_t length) {
                                    NSData* data = [[NSData alloc] initWithBytesNoCopy: (void*)bytes
                                                                                length: length
                                                                          freeWhenDone: NO];
                                    [slef appendDecodedData: data];
                                }];
        if (!ok)
            Warn(@"%@: ZDelta decoder error %d", self, _decompressor.status);
        return ok;
    } else {
        [self appendDecodedData: data];
        return YES;
    }
}

- (BOOL) closeFile {
    BOOL ok = YES;
    if (_decompressor) {
        ok = [self appendData: nil];        // flush zdelta decoder, write remaining decoded data
        _decompressor = nil;
    }
    if (_encryptor) {
        [_out writeData: _encryptor(nil)];  // write remaining encrypted data & clean up
        _encryptor = nil;
    }
    [_out closeFile];
    _out = nil;
    return ok;
}

- (BOOL) finish {
    Assert(_out, @"Already finished");
    if (![self closeFile])
        return NO;
    SHA1_Final(_blobKey.bytes, &_shaCtx);
    MD5_Final(_MD5Digest.bytes, &_md5Ctx);
    return YES;
}

- (NSString*) MD5DigestString {
    return [@"md5-" stringByAppendingString: [CBLBase64 encode: &_MD5Digest
                                                       length: sizeof(_MD5Digest)]];
}

- (NSString*) SHA1DigestString {
    return [@"sha1-" stringByAppendingString: [CBLBase64 encode: &_blobKey
                                                        length: sizeof(_blobKey)]];
}

- (NSData*) blobData {
    Assert(!_out, @"Not finished yet");
    NSData* data = [NSData dataWithContentsOfFile: _tempPath
                                          options: NSDataReadingMappedIfSafe
                                            error: NULL];
    CBLSymmetricKey* encryptionKey = _store.encryptionKey;
    if (encryptionKey && data)
        data = [encryptionKey decryptData: data];
    return data;
}

- (NSInputStream*) blobInputStream {
    Assert(!_out, @"Not finished yet");
    NSInputStream* stream = [NSInputStream inputStreamWithFileAtPath: _tempPath];
    [stream open];
    CBLSymmetricKey* encryptionKey = _store.encryptionKey;
    if (encryptionKey && stream)
        stream = [encryptionKey decryptStream: stream];
    return stream;
}

- (NSString*) filePath {
    return _store.encryptionKey ? nil : _tempPath;
}

- (BOOL) install {
    if (!_tempPath)
        return YES;  // already installed
    Assert(!_out, @"Not finished");
    // Move temp file to correct location in blob store:
    NSString* dstPath = [_store rawPathForKey: _blobKey];
    if ([[NSFileManager defaultManager] moveItemAtPath: _tempPath
                                                toPath: dstPath error:NULL]) {
        _tempPath = nil;
    } else {
        // If the move fails, assume it means a file with the same name already exists; in that
        // case it must have the identical contents, so we're still OK.
        [self cancel];
    }
    return YES;
}

- (void) cancel {
    [self closeFile];
    if (_tempPath) {
        [[NSFileManager defaultManager] removeItemAtPath: _tempPath error: NULL];
        _tempPath = nil;
    }
}

- (void) dealloc {
    [self cancel];      // Close file, and delete it if it hasn't been installed yet
}


@end
