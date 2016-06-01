//
//  CBLDynamicObject.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 8/6/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "CBLDynamicObject.h"
#import "MYLogging.h"
#import "Test.h"
#import <ctype.h>
#import <objc/runtime.h>


DefineLogDomain(Model);


@implementation CBLDynamicObject


// Abstract implementations for subclasses to override:

- (id) getValueOfProperty: (NSString*)property {
    NSAssert(NO, @"No such property %@.%@", [self class], property);
    return nil;
}

- (BOOL) setValue: (id)value ofProperty: (NSString*)property {
    return NO;
}


#pragma mark - SELECTOR-TO-PROPERTY NAME MAPPING:


NS_INLINE BOOL isGetter(const char* name) {
    if (!name[0] || name[0]=='_' || name[strlen(name)-1] == ':')
        return NO;                    // If it has parameters it's not a getter
    if (strncmp(name, "get", 3) == 0)
        return NO;                    // Ignore "getXXX" variants of getter syntax
    return YES;
}

NS_INLINE BOOL isSetter(const char* name) {
    return strncmp("set", name, 3) == 0 && name[strlen(name)-1] == ':';
}

// converts a getter selector to an NSString, equivalent to NSStringFromSelector().
NS_INLINE NSString *getterKey(SEL sel) {
    return [NSString stringWithUTF8String:sel_getName(sel)];
}

// converts a setter selector, of the form "set<Key>:" to an NSString of the form @"<key>".
NS_INLINE NSString *setterKey(SEL sel, BOOL upperCase) {
    const char* name = sel_getName(sel) + 3; // skip past 'set'
    size_t length = strlen(name);
    char buffer[1 + length];
    strcpy(buffer, name);
    if (!upperCase)
        buffer[0] = (char)tolower(buffer[0]);  // lowercase the property name
    buffer[length - 1] = '\0';       // and remove the ':'
    return [NSString stringWithUTF8String:buffer];
}


#pragma mark - PROPERTY INTROSPECTION:


+ (NSSet*) propertyNames {
    static NSMutableDictionary* classToNames;
    if (!classToNames)
        classToNames = [[NSMutableDictionary alloc] init];
    
    if (self == [CBLDynamicObject class])
        return [NSSet set];
    
    NSSet* cachedPropertyNames = [classToNames objectForKey:self];
    if (cachedPropertyNames)
        return cachedPropertyNames;
    
    NSMutableSet* propertyNames = [NSMutableSet set];
    objc_property_t* propertiesExcludingSuperclass = class_copyPropertyList(self, NULL);
    if (propertiesExcludingSuperclass) {
        objc_property_t* propertyPtr = propertiesExcludingSuperclass;
        while (*propertyPtr)
            [propertyNames addObject:[NSString stringWithUTF8String:property_getName(*propertyPtr++)]];
        free(propertiesExcludingSuperclass);
    }
    [propertyNames unionSet:[[self superclass] propertyNames]];
    [classToNames setObject: propertyNames forKey: (id)self];
    return propertyNames;
}


// Look up the encoded type of a property, and whether it's settable or readonly
static const char* getPropertyType(objc_property_t property, BOOL *outIsSettable) {
    *outIsSettable = YES;
    const char *result = "@";

    // Copy property attributes into a writeable buffer:
    const char *attributes = property_getAttributes(property);
    char buffer[1 + strlen(attributes)];
    strcpy(buffer, attributes);
    
    // Scan the comma-delimited sections of the string:
    char *state = buffer, *attribute;
    while ((attribute = strsep(&state, ",")) != NULL) {
        switch (attribute[0]) {
            case 'T':       // Property type in @encode format
                result = (const char *)[[NSData dataWithBytes: (attribute + 1) 
                                                       length: strlen(attribute)] bytes];
                break;
            case 'R':       // Read-only indicator
                *outIsSettable = NO;
                break;
        }
    }
    return result;
}


// Look up a class's property by name, and find its type and which class declared it
BOOL CBLGetPropertyInfo(Class cls,
                        NSString *propertyName,
                        BOOL setter,
                        Class *declaredInClass,
                        const char* *propertyType)
{
    // Find the property declaration:
    const char *name = [propertyName UTF8String];
    objc_property_t property = class_getProperty(cls, name);
    if (!property) {
        if (![propertyName hasPrefix: @"primitive"]) {   // Ignore "primitiveXXX" KVC accessors
            LogTo(Model, @"%@ has no dynamic property named '%@' -- failure likely",
                  cls, propertyName);
        }
        *propertyType = NULL;
        return NO;
    }

    // Find the class that introduced this property, as cls may have just inherited it:
    do {
        *declaredInClass = cls;
        cls = class_getSuperclass(cls);
    } while (class_getProperty(cls, name) == property);
    
    // Get the property's type:
    BOOL isSettable;
    *propertyType = getPropertyType(property, &isSettable);
    if (setter && !isSettable) {
        // Asked for a setter, but property is readonly:
        *propertyType = NULL;
        return NO;
    }
    return YES;
}


// subroutine for CBL___FromType. Invokes callback first with a module-qualified name (if any),
// then if that returns nil, with the base name. Necessary because the class name in the metadata
// doesn't include the class's module, so we have to guess it. (rdar://21368142)
static id lookUp(const char* baseName, Class relativeToClass, id (^callback)(const char*)) {
    if (relativeToClass && !strchr(baseName, '.')) {
        const char* relativeName = class_getName(relativeToClass);
        const char* dot = strchr(relativeName, '.');
        if (dot) {
            // relativeToClass is in a module, so first look for baseName in that module:
            int moduleLen = (int)(dot - relativeName);
            char fullName[moduleLen + strlen(baseName) + 2];
            sprintf(fullName, "%.*s.%s", moduleLen, relativeName, baseName);
            id result = callback(fullName);
            if (result)
                return result;
            // ...if not found in module, try again in without a module...
        }
    }
    return callback(baseName);
}


Class CBLClassFromType(const char* propertyType, Class relativeToClass) {
    size_t len = strlen(propertyType);
    if (propertyType[0] != _C_ID)
        return NULL;
    if (len == 1)
        return [NSObject class];    // Not quite right, but there's no class representing "id"
    if (len < 4 || propertyType[1] != '"' || propertyType[len-1] != '"') {
        Warn(@"CBLDynamicObject: Unknown type encoding: %s", propertyType);
        return NULL;
    }
    char className[len - 2];
    strlcpy(className, propertyType + 2, len - 2);
    char* bracket = strchr(className, '<');
    if (bracket) {
        if (bracket == className)
            return Nil;     // It's a pure protocol name
        *bracket = '\0';    // Strip any trailing protocol name(s)
    }

    return lookUp(className, relativeToClass, ^(const char* name) {
        return objc_getClass(name);
    });
}


Protocol* CBLProtocolFromType(const char* propertyType, Class relativeToClass) {
    size_t len = strlen(propertyType);
    if (propertyType[0] != _C_ID || propertyType[1] != '"' || propertyType[len-1] != '"'
                                 || propertyType[2] != '<' || propertyType[len-2] != '>')
        return NULL;
    char protocolName[len - 4];
    strlcpy(protocolName, propertyType + 3, len - 4);

    return lookUp(protocolName, relativeToClass, ^(const char* name) {
        return objc_getProtocol(name);
    });
}


static inline void setIdProperty(CBLDynamicObject *self, NSString* property, id value) {
    BOOL result = [self setValue: value ofProperty: property];
    NSCAssert(result, @"Property %@.%@ is not settable", [self class], property);
}


+ (Class) classOfProperty: (NSString*)propertyName {
    Class declaredInClass;
    const char* propertyType;
    if (!CBLGetPropertyInfo(self, propertyName, NO, &declaredInClass, &propertyType))
        return Nil;
    return CBLClassFromType(propertyType, self);
}


+ (id) impForGetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    return ^id(CBLDynamicObject* receiver) {
        return [receiver getValueOfProperty: property];
    };
}

+ (id) impForSetterOfProperty: (NSString*)property ofClass: (Class)propertyClass {
    return ^(CBLDynamicObject* receiver, id value) {
        setIdProperty(receiver, property, value);
    };
}


+ (id) impForGetterOfProperty: (NSString*)property ofProtocol: (Protocol*)propertyProtocol {
    return ^id(CBLDynamicObject* receiver) {
        return [receiver getValueOfProperty: property];
    };
}

+ (id) impForSetterOfProperty: (NSString*)property ofProtocol: (Protocol*)propertyProtocol {
    return ^(CBLDynamicObject* receiver, id value) {
        setIdProperty(receiver, property, value);
    };
}


+ (id) impForGetterOfProperty: (NSString*)property ofType: (const char*)propertyType {
    switch (propertyType[0]) {
        case _C_ID: {
            Class klass = CBLClassFromType(propertyType, self);
            if (klass)
                return [self impForGetterOfProperty: property ofClass: klass];
            Protocol* proto = CBLProtocolFromType(propertyType, self);
            if (proto)
                return [self impForGetterOfProperty: property ofProtocol: proto];
            Warn(@"CBLDynamicObject: %@.%@ has type %s which is not a known class or protocol",
                 self, property, propertyType);
            return nil;
        }
        case _C_INT:
        case _C_SHT:
        case _C_USHT:
        case _C_CHR:
        case _C_UCHR:
            return ^int(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] intValue];
            };
        case _C_UINT:
            return ^unsigned int(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] unsignedIntValue];
            };
        case _C_LNG:
            return ^long(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] longValue];
            };
        case _C_ULNG:
            return ^unsigned long(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] unsignedLongValue];
            };
        case _C_LNG_LNG:
            return ^long long(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] longLongValue];
            };
        case _C_ULNG_LNG:
            return ^unsigned long long(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] unsignedLongLongValue];
            };
        case _C_BOOL:
            return ^bool(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] boolValue];
            };
        case _C_FLT:
            return ^float(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] floatValue];
            };
        case _C_DBL:
            return ^double(CBLDynamicObject* receiver) {
                return [[receiver getValueOfProperty: property] doubleValue];
            };
        default:
            return nil;
    }
}

+ (id) impForSetterOfProperty: (NSString*)property ofType: (const char*)propertyType {
    switch (propertyType[0]) {
        case _C_ID: {
            Class klass = CBLClassFromType(propertyType, self);
            if (klass)
                return [self impForSetterOfProperty: property ofClass: klass];
            Protocol* proto = CBLProtocolFromType(propertyType, self);
            if (proto)
                return [self impForSetterOfProperty: property ofProtocol: proto];
            Warn(@"CBLDynamicObject: %@.%@ has type %s which is not a known class or protocol",
                 self, property, propertyType);
            return nil;
        }
        case _C_INT:
        case _C_SHT:
        case _C_USHT:
        case _C_CHR:            // Note that "BOOL" is a typedef so it compiles to 'char'
        case _C_UCHR:
            return ^(CBLDynamicObject* receiver, int value) {
                setIdProperty(receiver, property, [NSNumber numberWithInt: value]);
            };
        case _C_UINT:
            return ^(CBLDynamicObject* receiver, unsigned int value) {
                setIdProperty(receiver, property, [NSNumber numberWithUnsignedInt: value]);
            };
        case _C_LNG:
            return ^(CBLDynamicObject* receiver, long value) {
                setIdProperty(receiver, property, [NSNumber numberWithLong: value]);
            };
        case _C_ULNG:
            return ^(CBLDynamicObject* receiver, unsigned long value) {
                setIdProperty(receiver, property, [NSNumber numberWithUnsignedLong: value]);
            };
        case _C_LNG_LNG:
            return ^(CBLDynamicObject* receiver, long long value) {
                setIdProperty(receiver, property, [NSNumber numberWithLongLong: value]);
            };
        case _C_ULNG_LNG:
            return ^(CBLDynamicObject* receiver, unsigned long long value) {
                setIdProperty(receiver, property, [NSNumber numberWithUnsignedLongLong: value]);
            };
        case _C_BOOL:           // This is the true native C99/C++ "bool" type
            return ^(CBLDynamicObject* receiver, bool value) {
                setIdProperty(receiver, property, [NSNumber numberWithBool: value]);
            };
        case _C_FLT:
            return ^(CBLDynamicObject* receiver, float value) {
                setIdProperty(receiver, property, [NSNumber numberWithFloat: value]);
            };
        case _C_DBL:
            return ^(CBLDynamicObject* receiver, double value) {
                setIdProperty(receiver, property, [NSNumber numberWithDouble: value]);
            };
        default:
            return nil;
    }
}

// The Objective-C runtime calls this method when it's asked about a method that isn't natively
// implemented by this class. The implementation should either call class_addMethod and return YES,
// or return NO.
+ (BOOL)resolveInstanceMethod:(SEL)sel {
    const char *name = sel_getName(sel);
    NSString* key;
    Class declaredInClass;
    const char *propertyType = NULL;
    char signature[5];
    id accessor = nil;
    
    if (isSetter(name)) {
        // choose an appropriately typed generic setter function.
        for (int upperCase=NO; upperCase<=YES; upperCase++) {
            key = setterKey(sel, (BOOL)upperCase);
            if (CBLGetPropertyInfo(self, key, YES, &declaredInClass, &propertyType)) {
                strcpy(signature, "v@: ");
                signature[3] = propertyType[0];
                accessor = [self impForSetterOfProperty: key ofType: propertyType];
                break;
            }
        }
    } else if (isGetter(name)) {
        // choose an appropriately typed getter function.
        key = getterKey(sel);
        if (CBLGetPropertyInfo(self, key, NO, &declaredInClass, &propertyType)) {
            strcpy(signature, " @:");
            signature[0] = propertyType[0];
            accessor = [self impForGetterOfProperty: key ofType: propertyType];
        }
    } else {
        // Not a getter or setter name.
        return NO;
    }
    
    if (accessor) {
        LogVerbose(Model, @"Creating dynamic accessor method -[%@ %s]", declaredInClass, name);
        class_addMethod(declaredInClass, sel, imp_implementationWithBlock(accessor), signature);
        return YES;
    }
    
    if (propertyType) {
        Warn(@"Dynamic property %@.%@ has type '%s' unsupported by %@", 
             self, key, propertyType, self);
    }
    return NO;
}


@end
