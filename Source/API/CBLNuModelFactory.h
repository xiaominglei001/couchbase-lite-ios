//
//  CBLNuModelFactory.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/14.
//
//

#import "CBLNuModel.h"


@protocol CBLNuModelFactoryDelegate;


/** CBLNuModelFactory instantiates and tracks CBLNuModels.
    It's also responsible for loading and saving, but it delegates that. */
@interface CBLNuModelFactory : NSObject

/** The delegate, which is responsible for actually loading and saving model properties.
    Usually the CBLDatabase. */
@property (nonatomic, weak) id<CBLNuModelFactoryDelegate> delegate;

/** Adds a CBLNuModel class to the registry. Any document with a `type` property matching one of
    this class's +documentTypes will be instantiated as this class.
    It's a programmer error for two model classes to both claim the same document type; this will
    raise an exception when it occurs. */
- (void) registerModelClass: (Class)modelClass;

/** Returns the registered CBLNuModel subclass that claims this document type. */
- (Class) modelClassForDocumentType: (NSString*)docType;

/** Returns a model object for the given document ID.
    If a model has already been instantiated with the given ID, it must be returned (even if it's
    a fault.)
    @param documentID  The ID of the model
    @param ofClass  The class the model should be, or Nil if it can be any subclass.
    @param readProperties  If YES, the document properties are loaded immediately; 
                otherwise this may be deferred until a property value is requested. */
- (CBLNuModel*) modelWithDocumentID: (NSString*)documentID
                            ofClass: (Class)ofClass
                     readProperties: (BOOL)readProperties
                              error: (NSError**)outError;

/** Returns the existing non-fault model object with the given ID, or nil if there's none. */
- (CBLNuModel*) availableModelWithDocumentID: (NSString*)documentID;

/** All models whose needsSave is true. Models add/remove themselves from this set. */
@property (readonly) NSMutableSet* unsavedModels;

/** Saves changes to all models whose needsSave is true. */
- (BOOL) saveAllModels: (NSError**)outError;

/** Immediately runs any pending autosaves for all models. */
- (BOOL) autosaveAllModels: (NSError**)outError;

@end


@interface CBLNuModelFactory (Internal)

- (void) addModel: (CBLNuModel*)model;
- (BOOL) readPropertiesOfModel: (CBLNuModel*)model error: (NSError**)error;
- (BOOL) savePropertiesOfModel: (CBLNuModel*)model error: (NSError**)error;

@end


/** Protocol for classes that can load and save CBLNuModel objects' persistent state.
    (This is implemented by CBLDatabase.) */
@protocol CBLNuModelFactoryDelegate <NSObject>

- (BOOL) readPropertiesOfModel: (CBLNuModel*)model error: (NSError**)error;
- (BOOL) savePropertiesOfModel: (CBLNuModel*)model error: (NSError**)error;

- (BOOL) savePropertiesOfModels: (NSSet*)models error: (NSError**)outError;

@end
