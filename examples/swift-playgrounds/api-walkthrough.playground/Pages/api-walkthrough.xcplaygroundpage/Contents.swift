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
 Run the following steps to install a pre-built database and start using the 2.0 API.
 1. Download [todo.zip](https://cl.ly/3G453b0T1M1q/todo.zip)
    - 1.x pre-built database with a single list called **Groceries**.
    ![](groceries.png)
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
var database = try Database(name: "todo")
/*:
 - Experiment:
 Use the `Database(name: String, options: DatabaseOptions)` initializer to open the existing **todo** database.
*/
var options = DatabaseOptions()
options.directory = documentsDirectory.path
database = try Database(name: "todo", options: options)
/*:
 - Experiment:
 Iterate over all the documents in the database (print the `id` and `type` properties). You should see that there are `task` and `task-list` documents already.
*/
for (index, row) in database.allDocuments.enumerated() {
    let string = "id \(row.id), type \(row.getString("type"))"
}
/*:
 ## Create Document
 ### 1.x API
 - `getDocument` method to get or create a document.
 ### 2.0 API
 - `getDocument` returns nil if the document doesn't exist.
 - `Document` initializers to create a new Document.
*/
let dict: [String: Any] = ["type": "task",
                           "owner": "todo",
                           "createdAt": Date()]
let newTask = Document(dictionary: dict)
try database.save(newTask)
/*:
 - Experiment:
 Print the properties of the `newTask` document.
*/
newTask.toDictionary()
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
 Add the missing `name` field to the `newTask` document.
 */
newTask.set("Croissant", forKey: "name")
try database.save(newTask)
/*:
 - Experiment:
 Verify that the property was successfully modified.
*/
newTask.toDictionary()
/*:
 - Experiment:
 The getter methods are chainable.
    1. Get the document with id `todo.123`.
    2. Add 2 new tasks item under the `tasks` property.
    3. Save the document and verify that the tasks were added successfully.
*/
let newList = Document(dictionary: ["name": "Holidays", "type": "task-list"])
newList.set([], forKey: "tasks")
    .getArray("tasks")?.add(["name": "Spade", "complete": false])
                       .add(["name": "Sandpit", "complete": false])
try database.save(newList)
newList.getArray("tasks")?.count
/*:
 ## Index
 - What is an index?
 ### 1.x API
 - In 1.x, a query index is created using the View API.
 - It is a map/reduce function that runs against all the documents.
 ### 2.0 API
 - It will speed up queries that test that property.
 - Creating an index is optional.
*/
try database.createIndex(["type"])
/*:
 ## Query
 ### 1.x API
 - A Query is instantiated with the `createQuery()` method.
 - Query options such as `limit`, `descending` are set on the query object.
 ### 2.0 API
 - Unified cross-platform query API.
 - To see if a query uses an index, call the `explain()` method.
 - With an index, the query will run a binary search instead of a linear scan.
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
let croissantPicture = #imageLiteral(resourceName: "croissant.jpg")
let imageData = UIImageJPEGRepresentation(croissantPicture, 1)!
/*:
 - Experiment:
 Persist the `imageData` value as a blob named `image` with a content-type of `image/jpg`.
*/
let blob = Blob(contentType: "image/jpg", data: imageData)
newTask.set(blob, forKey: "image")
try database.save(newTask)
/*:
 - Experiment:
 Print the properties of the `newTask` document.
 */
newTask.toDictionary()
/*:
 ## Typed accessors
 ### 1.x API
 - Required type casting when accessing a property.
 ### 2.0 API
 - Typed accessors provided for all JSON types and `Blob`.
*/
newTask.getString("name")
newTask.getDate("createdAt")
/*:
 - Experiment:
 Use the `getBlob()` type accessor to display the image in the playground as a `UIImage`.
 */
if let taskBlob = newTask.getBlob("image") {
    UIImage(data: taskBlob.content!)
}
/*:
 ## Replication
 ### 1.x API
 - Push/pull replication methods.
 ### 2.0 API
 - Replication is always bi-directional.
 - Methods to enabled push or pull.
*/
let url = URL(string: "blip://localhost:4984/db")!
let replication = database.replication(with: url)
replication.start()
/*:
 - Experiment:
 Use the `PlaygroundPage.current.needsIndefiniteExecution = true` statement to execute the playground indefinitely.
*/

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
