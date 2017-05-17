//: [Previous](@previous)
//: # Develop with Couchbase Mobile 2.0:
//: # Data Management, Sync, and Security.
import Foundation
import UIKit
import CouchbaseLiteSwift
import PlaygroundSupport

let documentsDirectory = playgroundSharedDataDirectory.resolvingSymlinksInPath()
/*:
 ## Getting Started
 The pre-built database from the 1.x online tutorial can be used in this playground. Run the following steps to install it.
 1. Download [todo.zip](https://cl.ly/3G453b0T1M1q/todo.zip)
 2. Create the directory `~/Documents/Shared Playground Data`
 3. Unzip the downloaded file and move `todo.cblite2` to the playground data folder.
 ## Creating a Database
 - A database is simply a collection of documents.
 - Server-less architecture; All logic is embedded in the application.
 ### 1.x API
 - `Manager` class to set top-level properties (storage directory, logging).
 ### 2.0 API
 - No `Manager` class.
 - Instead databases are created using the `Database` initializer.
*/
let emptyDatabase = try Database(name: "todo")
/*:
 - Experiment:
 Use the `Database(name: String, options: DatabaseOptions)` initializer to open the existing **todo** database.
*/
var options = DatabaseOptions()
options.directory = documentsDirectory.path
let database = try Database(name: "todo", options: options)
/*:
 - Experiment:
 Iterate over all the documents in the database (print the `id` and `type` properties). You should see that there are `task` and `task-list` documents already.
*/
for (index, row) in database.allDocuments.enumerated() {
//    let string = "id \(row.id), type \(row.getString("type"))"
}
/*:
 ## Create Document
 ### 1.x API
 - `getDocument` method to get or create a document.
 ### 2.0 API
 - `getDocument` returns nil if the document doesn't exist.
 - `Document` initializers to create a new Document.
*/
let dict: [String: Any] = ["type": "task-list",
                           "owner": "todo"]
let movieList = Document("movie.123", dictionary: dict)
try database.save(movieList)
/*:
 - Experiment:
 Print the properties of the `movieList` document.
*/
movieList.toDictionary()
/*:
 ## Update Document
 - `Document` properties are now mutable.
 ### 1.x API
 - `Document` properties are immutable.
 - Must create an immutable copy of the properties to make changes.
 ### 2.0 API
 - `Document` properties are now mutable.
 - Changes can be made in place.
*/
/*:
 - Experiment:
 Add the missing `name` field to the `movieList` document.
 */
movieList.set("Movie", forKey: "name")
try database.save(movieList)
movieList.toDictionary()
// Changing a nested property: Dictionary API in DB7 (can also be done in the Fragment API - similar to SwiftyJSON)
/*:
 - Experiment:
 Verify that the property was successfully modified.
*/
movieList.getString("name")
/*:
 ## Threading model
 - Same threading model across platforms.
 - Couchbase Lite objects are thread safe.
 - When getting a document multiple times, even on the same thread, it will return different instances of the Document.
 */
/*:
 - Experiment:
     1. Create two instances of the same document.
     2. Print the address of each instance to the console.
     3. Notice the address of each instance is different.
*/
var list1 = database.getDocument("todo.123")
var list2 = database.getDocument("todo.123")
// re-write this closure to be the more descriptive form
withUnsafePointer(to: &list1) {
    $0
}
withUnsafePointer(to: &list2) {
    $0
}
/*:
 ## Index
 - What is an index?
 ### 1.x API
 - In 1.x, a query index is created using the View API.
 - It is a map/reduce function that runs against all the documents.
 ### 2.0 API
 - It will speed up queries that test that property.
 - Creating an index is optional.
 - To see if a query uses an index, call the `explain()` method.
 - With an index, the query will run a binary search instead of a linear scan.
*/
try database.createIndex(["type"])
/*:
 ## Query
 ### 1.x API
 - A Query is instantiated with the `createQuery()` method.
 - Query options such as `limit`, `descending` are set on the query object.
 ### 2.0 API
*/
let typeQuery = Query
             .select()
             .from(DataSource.database(database))
             .where(Expression.property("type").equalTo("task-list"))
for (index, row) in try typeQuery.run().enumerated() {
    row.documentID
}
try typeQuery.explain()
/*:
 - Experiment:
 Run a query on a property that isn't being indexed and notice the difference in the `explain()` query statement.
*/
let nameQuery = Query
    .select()
    .from(DataSource.database(database))
    .where(Expression.property("name").equalTo("Groceries"))
for (index, row) in try nameQuery.run().enumerated() {
    row.documentID
}
try nameQuery.explain()
/*:
 - Note:
 For more query examples, refer to the Query + FTS playground.
*/
/*:
 ## Blob
 ### 1.x API
 - Exposed through the `Revision` API.
 ### 2.0 API
 - Treated the same as other data types.
*/
let painAuChocolat = #imageLiteral(resourceName: "croissant.jpg")
let imageData = UIImageJPEGRepresentation(painAuChocolat, 1)!
/*:
 - Experiment:
 Persist the `imageData` value as a blob name `image` with a content-type of `image/jpg`.
*/
let blob = Blob(contentType: "image/jpg", data: imageData)
movieList.set(blob, forKey: "image")
try database.save(movieList)
/*:
 - Experiment:
 Print the properties of the `movieList` document.
 */
movieList.toDictionary()
/*:
 ## Typed accessors
 ### 1.x API
 - Required type casting when accessing a property.
 ### 2.0 API
 - Typed accessors provided for all JSON types and `Blob`.
*/
// are attachments upgrade going to be supported.
let appleQuery = Query
    .select()
    .from(DataSource.database(database))
    .where(Expression.property("task").equalTo("apples"))
for (index, row) in try appleQuery.run().enumerated() {
    let task = row.document.getString("task")
    let date = row.document.getDate("createdAt")
    let image = row.document.getBlob("_attachments")
    image?.content
}
/*:
 - Experiment:
 Use the `getBlob()` type accessor to display the image in the playground as a `UIImage`.
 */
if let taskBlob = movieList.getBlob("image") {
    UIImage(data: taskBlob.content!)
}
/*:
 ## Replication
 ### 1.x API
 - Push/pull replication methods.
 ### 2.0 API
 - Replication is always bi-directional.
*/
let url = URL(string: "blip://localhost:4984/db")!
let replication = database.replication(with: url)
PlaygroundPage.current.needsIndefiniteExecution = true
/*:
  With `.needsIndefiniteExecution = true`, we must explicitly call `PlaygroundPage.current.finishExecution()` when the asynchronous operation has completed.
 - Experiment:
 Implement the replication change listener and call `PlaygroundPage.current.finishExecution()` once the replication has completed.
*/
public class ReplicationListener: ReplicationDelegate {
    public init() {
        
    }
    public func replication(_ replication: CBLReplication, didChange status: Replication.Status) {
        print(status)
    }
    public func replication(_ replication: CBLReplication, didStopWithError error: Error?) {
        print(error)
    }
}
replication.delegate = ReplicationListener()
replication.continuous = true
replication.start()
/*:
 ## Conflict Resolvers
 ### 1.x API
 - Conflict resolution was an opt-in API.
 ### 2.0 API
 - No `Revision` API, no access to revision history and conflicting revisions.
 - Conflicts are resolved when a document is saved or during replication (prevents unresolved conflicts).
 - By default, the conflict with the larger number of changes in its history wins.
 - Can be specified either at the database or document level.
*/
