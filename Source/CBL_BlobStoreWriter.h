//
//  CBL_BlobStoreWriter.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/2/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_BlobStore.h"


/** Lets you stream a large attachment to a CBL_BlobStore asynchronously, e.g. from a network download. */
@interface CBL_BlobStoreWriter : NSObject

- (instancetype) initWithStore: (CBL_BlobStore*)store;

/** Tells the writer that the incoming data stream is gzip-compressed. It will decode and write the
    target data incrementally. */
- (void) decodeGZip;

/** Tells the writer that the incoming data stream is a delta in zdelta format, whose base data is
    the attachment with the given `sourceKey`. The writer will decode and write the target data
    incrementally. */
- (BOOL) decodeZDeltaFrom: (CBLBlobKey)sourceKey;

/** Appends data to the blob. Call this when new data is available. */
- (BOOL) appendData: (NSData*)data;

/** Call this after all the data has been added. */
- (BOOL) finish;

/** Call this to cancel before finishing the data. */
- (void) cancel;

/** Installs a finished blob into the store. */
- (BOOL) install;

/** The number of bytes in the blob. */
@property (readonly) UInt64 length;

/** The contents of the blob. */
@property (readonly) NSData* blobData;

/** After finishing, this is the key for looking up the blob through the CBL_BlobStore. */
@property (readonly) CBLBlobKey blobKey;

/** After finishing, this is the SHA-1 digest of the blob, in base64 with a "sha1-" prefix. */
@property (readonly) NSString* SHA1DigestString;

/** After finishing, this is the MD5 digest of the blob, in base64 with an "md5-" prefix.
    (This is useful for compatibility with CouchDB, which stores MD5 digests of attachments.) */
@property (readonly) NSString* MD5DigestString;

/** The location of the temporary file containing the attachment contents.
    Will be nil after -install is called. */
@property (readonly) NSString* filePath;

/** A stream for reading the completed blob. */
- (NSInputStream*) blobInputStream;

@end
