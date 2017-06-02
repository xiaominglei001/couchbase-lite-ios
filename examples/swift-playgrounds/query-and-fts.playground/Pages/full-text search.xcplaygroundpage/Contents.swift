//: # Full-Text Search in Couchbase Mobile 2.0
import CouchbaseLiteSwift
import PlaygroundSupport
let documentsDirectory = playgroundSharedDataDirectory.path
/*:
 ## Getting Started
 Run the following steps to install a pre-built database and start using the 2.0 API.
 1. Download [travel-sample.zip](https://cl.ly/2m1I2g21102h/travel-sample.zip)
    - 1.x pre-built database of the travel-sample bucket.
    ![](travel-sample.png)
 2. Create the `~/Documents/Shared Playground Data` directory.
 3. Unzip the downloaded file and move `travel-sample.cblite2` to the playground data folder.
 */
var config = DatabaseConfiguration()
config.directory = documentsDirectory
let database = try Database(name: "travel-sample", config: config)
/*:
 - Experiment:
 Find out how many documents are in the database.
 */
for (index, row) in database.allDocuments.enumerated() {
    "type \(row.string(forKey: "type"))"
}
/*:
 ## Hotel Search
 ### Full-Text Search Index
 - To search on documents, an index must be created first on the properties we wish to query.
 - FTS will not work without an index.
 - The array is the primary and secondary key. The index ordering is based on those and is purely used for performance.
 - Generally, best to stick to 1 property in the index.
*/
//let hotelSearchIndex = try database.createIndex(["description"], options: IndexOptions.fullTextIndex(language: nil, ignoreDiacritics: false))
/*:
 - Note:
 Need to find a way to know if the index already exists.
*/
/*:
 ### Full-Text Search Query
 - Running a full-text search query is similar to a normal query. The difference is that the result row type is `FullTextQueryRow` which has additional methods.
*/
let hotelSearchQuery = Query
                        .select()
                        .from(DataSource.database(database))
                        .where(Expression.property("description").match("'seafront'"))
for row in try hotelSearchQuery.run() {
    if let ftsRow = row as? FullTextQueryRow {
        "hotelSearchQuery :: \(ftsRow.fullTextMatched!)"
    }
}
/*:
 - Note:
    - Any time the match operator it runs FTS and returns FullTextQueryRow
    - SQLite FTS4 has special DSL like '' and * to make the search for granular if we talk about it since it diverges from N1QL
*/
