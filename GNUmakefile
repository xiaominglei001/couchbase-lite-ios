# Couchbase Lite Makefile for GNUstep

# Include the common variables defined by the Makefile Package
include $(GNUSTEP_MAKEFILES)/common.make

# Build a simple Objective-C program
FRAMEWORK_NAME = CouchbaseLite

# The Objective-C files to compile
CouchbaseLite_OBJC_FILES = \
	Source/API/CBLAttachment.m             \
	Source/API/CBLAuthenticator.m          \
	Source/API/CBLDatabase.m               \
	Source/API/CBLDocument.m               \
	Source/API/CBLGeometry.m               \
	Source/API/CBLJSON.m                   \
	Source/API/CBLManager.m                \
	Source/API/CBLQuery+FullTextSearch.m   \
	Source/API/CBLQuery+Geo.m              \
	Source/API/CBLQuery.m                  \
	Source/API/CBLReplication+Transformation.m \
	Source/API/CBLReplication.m            \
	Source/API/CBLRevision.m               \
	Source/API/CBLView.m                   \
	\
	Source/CBJSONEncoder.m                 \
	Source/CBLAuthorizer.m                 \
	Source/CBLBase64.m                     \
	Source/CBLBatcher.m                    \
	Source/CBLBulkDownloader.m             \
	Source/CBLCache.m                      \
	Source/CBLCollateJSON.m                \
	Source/CBLDatabase+Attachments.m       \
	Source/CBLDatabase+Insertion.m         \
	Source/CBLDatabase+Internal.m          \
	Source/CBLDatabase+LocalDocs.m         \
	Source/CBLDatabase+Replication.m       \
	Source/CBLDatabaseChange.m             \
	Source/CBLGNUstep.m                    \
	Source/CBLJSONReader.m                 \
	Source/CBLJSONValidator.m              \
	Source/CBLJSONValidatorTests.m         \
	Source/CBLMisc.m                       \
	Source/CBLMultiStreamWriter.m          \
	Source/CBLMultipartDocumentReader.m    \
	Source/CBLMultipartDownloader.m        \
	Source/CBLMultipartReader.m            \
	Source/CBLMultipartUploader.m          \
	Source/CBLMultipartWriter.m            \
	Source/CBLRemoteRequest.m              \
	Source/CBLRouter+Changes.m             \
	Source/CBLSequenceMap.m                \
	Source/CBLStatus.m                     \
	Source/CBLTokenAuthorizer.m            \
	Source/CBLView+Internal.m              \
	Source/CBLView+Querying.m              \
	Source/CBL_Attachment.m                \
	Source/CBL_BlobStore.m                 \
	Source/CBL_Body.m                      \
	Source/CBL_Puller.m                    \
	Source/CBL_Pusher.m                    \
	Source/CBL_Replicator.m                \
	Source/CBL_Revision.m                  \
	Source/CBL_Server.m                    \
	Source/CBL_Shared.m                    \
    \
	Source/ChangeTracker/CBLChangeMatcher.m           \
	Source/ChangeTracker/CBLChangeTracker.m           \
	Source/ChangeTracker/CBLSocketChangeTracker.m     \
	Source/ChangeTracker/CBLWebSocketChangeTracker.m  \
	\
    vendor/fmdb/src/FMDatabaseAdditions.m \
    vendor/fmdb/src/FMDatabase.m \
    vendor/fmdb/src/FMResultSet.m \
    \
    vendor/MYUtilities/CollectionUtils.m \
    vendor/MYUtilities/ExceptionUtils.m \
    vendor/MYUtilities/Logging.m \
    vendor/MYUtilities/MYBlockUtils.m \
    vendor/MYUtilities/Test.m \
    \
    vendor/google-toolbox-for-mac/GTMNSData+zlib.m

# Skipped:
#   Source/CBLJSFunction.m                 \
#   Source/CBLJSViewCompiler.m             \
#   Source/API/CBLModel.m                  \
#   Source/API/CBLModel+Properties.m       \
#   Source/API/CBLModelArray.m             \
#   Source/API/CBLModelFactory.m           \
#	Source/API/CBLQueryBuilder.m           \
#	Source/API/CBLReduceFuncs.m            \
#	Source/CBLFacebookAuthorizer.m         \
#	Source/CBLOAuth1Authorizer.m           \
#	Source/CBLPersonaAuthorizer.m          \
#	Source/CBLReachability.m               \
#	Source/CBLRegisterJSViewCompiler.m     \
#	Source/CBL_Router+Handlers.m           \
#	Source/CBL_Router.m                    \
#	Source/CBL_URLProtocol.m               \

CouchbaseLite_HEADER_FILES_DIR = Source/API
CouchbaseLite_HEADER_FILES = \
	CouchbaseLite.h \
	CBLAttachment.h \
	CBLAuthenticator.h \
	CBLDatabase.h \
	CBLDocument.h \
	CBLGeometry.h \
	CBLJSON.h \
	CBLManager.h \
	CBLModel.h \
	CBLModelArray.h \
	CBLModelFactory.h \
	CBLQuery.h \
	CBLQuery+FullTextSearch.h \
	CBLQuery+Geo.h \
	CBLQueryBuilder.h \
	CBLReduceFuncs.h \
	CBLReplication.h \
	CBLRevision.h \
	CBLView.h

CouchbaseLite_INCLUDE_DIRS = \
    -ISource \
	-ISource/API \
    -ISource/ChangeTracker \
    -Ivendor/fmdb/src \
    -Ivendor/google-toolbox-for-mac \
    -Ivendor/MYUtilities \
    -Ivendor/sqlite3-unicodesn \
    -Ivendor/WebSockets-Cocoa/WebSocket \
    -Ivendor/yajl/build/yajl-2.0.5/include

CouchbaseLite_OBJCFLAGS = \
	-fobjc-arc \
	-fobjc-runtime=gnustep-1.7 \
	-include Source/CouchbaseLitePrefix.h \
    -DCBL_VERSION_NUMBER=1.1 \
    -DCBL_VERSION_STRING=\"1.1-GNUstep\"
    


TOOL_NAME = CBLTool

CBLTool_OBJC_FILES = Demo-Mac/EmptyGNUstepApp.m

CBLTool_OBJCFLAGS = \
    -include Source/CBLGNUstep.h

CBLTool_OBJC_LIBS = \
    -lCouchbaseLite  -LCouchbaseLite.framework \
    -lsqlite3 \
    -lcrypto \
    -luuid

CBLTool_INCLUDE_DIRS = \
    -Ivendor/MYUtilities


OBJCFLAGS = \
	-fblocks \
    -Werror \
    -Wall \
    -DDEBUG=1 \
	-I/usr/include/GNUstep
#??? Why do I need to add /usr/include/GNUstep myself???
    
#LDFLAGS = -v

-include GNUmakefile.preamble

# Include in the rules for making GNUstep frameworks
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble

