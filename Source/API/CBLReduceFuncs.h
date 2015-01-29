//
//  CBLReduceFuncs.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/14.
//
//

#import "CBLView.h"

void CBLRegisterReduceFunc(NSString* name, CBLReduceBlock block);

CBLReduceBlock CBLGetReduceFunc(NSString* name);
