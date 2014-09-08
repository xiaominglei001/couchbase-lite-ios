//
//  CBLRemoteQuery.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/5/14.
//
//

#import "CBLRemoteQuery.h"
#import "CBLQuery+Geo.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLRemoteRequest.h"
#import "CBLMisc.h"


@interface CBLRemoteQuery () <CBLRemoteRequestDelegate>
@end


@implementation CBLRemoteQuery
{
    NSURL* _remoteDB;
    NSString* _designDocID, *_viewName;
}

@synthesize puller=_puller;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remoteDB
                             view: (NSString*)viewName
{
    Assert(remoteDB);
    self = [super initWithDatabase: database view: nil];
    if (self) {
        _remoteDB = remoteDB;
        if (viewName) {
            NSArray* components = [viewName componentsSeparatedByString: @"/"];
            if (components.count != 2)
                return nil;
            _designDocID = components[0];
            _viewName = components[1];
        }
        self.mapOnly = NO;
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database mapBlock: (CBLMapBlock)mapBlock {
    Assert(NO, @"This should not be called");
}

- (CBLLiveQuery*) asLiveQuery {
    Assert(NO, @"Remote live queries are not supported (yet?)");
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"%@[%@ %@/%@]",
            self.class, _remoteDB.absoluteString, _designDocID, _viewName];
}


static void addNumParam(NSMutableString* urlStr, NSString* name, NSUInteger param) {
    if (param > 0)
        [urlStr appendFormat: @"&%@=%lu", name, (unsigned long)param];
}

static void addStringParam(NSMutableString* urlStr, NSString* name, NSString* param) {
    if (param)
        [urlStr appendFormat: @"&%@=%@", name, CBLEscapeURLParam(param)];
}

static void addJSONParam(NSMutableString* urlStr, NSString* name, id param) {
    if (param) {
        NSString* str = [CBLJSON stringWithJSONObject: param options: CBLJSONWritingAllowFragments error: NULL];
        Assert(str, @"Can't encode JSON value for URL param %@", name);
        addStringParam(urlStr, name, str);
    }
}


- (NSURL*) queryURL {
    static NSString* const kIndexUpdateModeNames[] = {@"false", @"ok", @"update_after"};

    NSMutableString* urlStr = [_remoteDB.absoluteString mutableCopy];
    if (![urlStr hasSuffix: @"/"])
        [urlStr appendString: @"/"];
    if (_designDocID)
        [urlStr appendFormat: @"_design/%@/_view/%@?", _designDocID, _viewName];
    else {
        [urlStr appendString: @"_all_docs?"];
        if (self.allDocsMode == kCBLIncludeDeleted)
            [urlStr appendString: @"&include_deleted=true"];
    }

    addNumParam(urlStr, @"skip", self.skip);
    if (self.limit < UINT_MAX)
        addNumParam(urlStr, @"limit", self.limit);
    addNumParam(urlStr, @"group_level", self.groupLevel);
    addJSONParam(urlStr, @"startkey", self.startKey);
    addJSONParam(urlStr, @"endkey", self.endKey);
    addStringParam(urlStr, @"startkey_docid", self.startKeyDocID);
    addStringParam(urlStr, @"endkey_docid", self.endKeyDocID);
    addStringParam(urlStr, @"stale", kIndexUpdateModeNames[self.indexUpdateMode]);
    if (!self.inclusiveEnd)
        [urlStr appendString: @"&inclusive_end=false"];
    if (self.descending)
        [urlStr appendString: @"&descending=true"];
    if (self.prefetch)
        [urlStr appendString: @"&include_docs=true"];
    if (self.mapOnly)
        [urlStr appendString: @"&reduce=false"];
    if (self.allDocsMode)
        [urlStr appendString: @"&descending=true"];
    return [NSURL URLWithString: urlStr];
}


- (CBLQueryEnumerator*) run: (NSError**)outError {
    __block BOOL complete = NO;
    __block CBLQueryEnumerator* result = nil;
    [self runAsync: ^(CBLQueryEnumerator *e, NSError *error) {
        result = e;
        if (outError)
            *outError = error;
        complete = YES;
    }];

    while (!complete) {
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate distantFuture]];
    }
    return result;
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete {
    if (!self.inclusiveStart || self.prefixMatchLevel > 0 || self.fullTextQuery || _isGeoQuery) {
        Warn(@"%@ is using options not supported for remote queries", self);
        onComplete(nil, CBLStatusToNSError(kCBLStatusNotImplemented, nil));
        return;
    }

    NSPredicate* postFilter = self.postFilter;
    NSArray* sortDescriptors = self.sortDescriptors;

    CBLRemoteJSONRequest* rq;
    rq = [[CBLRemoteJSONRequest alloc] initWithMethod: @"GET"
                                                  URL: self.queryURL
                                                 body: nil
                                       requestHeaders: nil
                                         onCompletion: ^(NSDictionary* result, NSError *error)
    {
        CBLQueryEnumerator* e = nil;
        if (error) {
            LogTo(Query, @"%@ failed: %@", self, error);
        } else {
            NSArray* rows = [$castIf(NSArray, result[@"rows"]) my_map: ^id(NSDictionary* rowDict) {
                NSString* docID = $castIf(NSString, rowDict[@"id"]);
                CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: docID
                                                             sequence: 0
                                                                  key: rowDict[@"key"]
                                                                value: rowDict[@"value"]
                                                        docProperties: rowDict[@"doc"]];
                if (postFilter && ![postFilter evaluateWithObject: row])
                    return nil;
                return row;
            }];
            if (sortDescriptors)
                rows = [rows sortedArrayUsingDescriptors: self.sortDescriptors];
            LogTo(Query, @"%@ finished: %lu rows", self, (unsigned long)rows.count);
            e = [[CBLQueryEnumerator alloc] initWithDatabase: self.database
                                                        rows: rows
                                              sequenceNumber: 0];
        }
        onComplete(e, error);
    }];
    if (!_puller)
        _puller = [self.database existingReplicationWithURL: _remoteDB pull: YES];
    rq.authorizer = (id<CBLAuthorizer>)_puller.authenticator;
    rq.delegate = self;
    [rq start];
}


@end
