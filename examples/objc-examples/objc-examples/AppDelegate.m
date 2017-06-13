//
//  AppDelegate.m
//  objc-examples
//
//  Created by James Nocentini on 13/06/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

#import "AppDelegate.h"
#include <CouchbaseLite/CouchbaseLite.h>

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    // create database
    NSError *error;
    CBLDatabase* database = [[CBLDatabase alloc] initWithName:@"my-database" error:&error];
    if (!database) {
        NSLog(@"Cannot open the database: %@", error);
    }
    
    // create document
    NSError* error;
    CBLDocument* newTask = [[CBLDocument alloc] init];
    [newTask setObject:@"task-list" forKey:@"type"];
    [newTask setObject:@"todo" forKey:@"owner"];
    [newTask setObject:[NSDate date] forKey:@"createAt"];
    [database saveDocument: newTask error: &error];
    
    // mutate document
    [newTask setObject:@"Apples" forKey:@"name"];
    [database saveDocument:newTask error:&error];
    
    // typed accessors
    [newTask setObject:[NSDate date] forKey:@"createdAt"];
    NSDate* date = [newTask dateForKey:@"createdAt"];
    
    // database transaction
    [database inBatch:&error do:^{
        for (int i = 1; i <= 10; i++)
        {
            NSError* error;
            CBLDocument *doc = [[CBLDocument alloc] init];
            [doc setObject:@"user" forKey:@"type"];
            [doc setObject:[NSString stringWithFormat:@"user %d", i] forKey:@"name"];
            [database saveDocument:doc error:&error];
            NSLog(@"saved user document %@", [doc stringForKey:@"name"]);
        }
    }];
    
    // blob
    UIImage *image = [UIImage imageNamed:@"avatar.jpg"];
    NSData *data = UIImageJPEGRepresentation(image, 1);
    
    CBLBlob *blob = [[CBLBlob alloc] initWithContentType:@"image/jpg" data:data];
    [newTask setObject:blob forKey: @"avatar"];
    
    NSError* error;
    [database saveDocument: newTask error:&error];
    if (error) {
        NSLog(@"Cannot save document %@", error);
    }
    
    CBLBlob* taskBlob = [newTask blobForKey:@"avatar"];
    UIImage* image = [UIImage imageWithData:taskBlob.content];
    
    // query
    CBLQuery* query = [CBLQuery select:[CBLQuerySelect all]
                                  from:[CBLQueryDataSource database:database]
                                 where:[
                                        [[CBLQueryExpression property:@"type"] equalTo:@"user"]
                                        and: [[CBLQueryExpression property:@"admin"] equalTo:@FALSE]]];
    
    NSEnumerator* rows = [query run:&error];
    for (CBLQueryRow *row in rows) {
        NSLog(@"doc ID :: %@", row.documentID);
    }
    
    // fts example
    // insert documents
    NSArray *tasks = @[@"buy groceries", @"play chess", @"book travels", @"buy museum tickets"];
    for (NSString* task in tasks) {
        CBLDocument* doc = [[CBLDocument alloc] init];
        [doc setObject: @"task" forKey: @"type"];
        [doc setObject: task forKey: @"name"];
        
        NSError* error;
        [database saveDocument: newTask error:&error];
        if (error) {
            NSLog(@"Cannot save document %@", error);
        }
    }
    
    // create index
    [database createIndexOn:@[@"name"] type:kCBLFullTextIndex options:NULL error:&error];
    if (error) {
        NSLog(@"Cannot create index %@", error);
    }
    
    CBLQueryExpression* where = [[CBLQueryExpression property:@"name"] match:@"'buy'"];
    CBLQuery *ftsQuery = [CBLQuery select:[CBLQuerySelect all]
                                     from:[CBLQueryDataSource database:database]
                                    where:where];
    
    NSEnumerator* ftsQueryResult = [ftsQuery run:&error];
    for (CBLFullTextQueryRow *row in ftsQueryResult) {
        NSLog(@"document properties :: %@", [row.document toDictionary]);
    }
    
    // replication
    NSURL *url = [[NSURL alloc] initWithString:@"blip://localhost:4984/db"];
    
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] init];
    config.database = database;
    config.target = [CBLReplicatorTarget url: url];
    config.continuous = YES;
    
    CBLReplicator *replication = [[CBLReplicator alloc] initWithConfig: config];
    [replication start];
    
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


@end
