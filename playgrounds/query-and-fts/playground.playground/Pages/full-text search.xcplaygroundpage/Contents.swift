//: # Full-Text Search in Couchbase Mobile 2.0
import CouchbaseLiteSwift
import PlaygroundSupport
let documentsDirectory = playgroundSharedDataDirectory.path
/*:
 ## Pre-existing database
 - Database with the same data as the travel sample data.
 - Replicated to a 1.x instance.
 - Opened with 2.0 (automatically upgraded).
 */
var options = DatabaseOptions()
options.directory = documentsDirectory
let database = try? Database(name: "travel-sample", options: options)
for (index, row) in database!.allDocuments.enumerated() {
    //    print(row)
}

/*:
 ## Hotel Search
 ### Full-Text Search Index
 - To search on documents, an index must be created first on the properties we wish to query.
*/
let hotelSearchIndex = try? database!.createIndex(["description"], options: IndexOptions.fullTextIndex(language: nil, ignoreDiacritics: false))
// FTS will not work without an index
// the array is the primary key and secondary key. and the ordering is based on that. the ordering in the index is purely for performance.
// generally, stick to one property in the index.
// For FTS it doesn't make any sense.

// the ñ example for now
/*:
 ### Full-Text Search Query
 - Running a full-text search query is similar to a normal query. The difference is that the result row type is `FullTextQueryRow` which has additional methods.
*/
let hotelSearchQuery = Query
                        .select()
                        .from(DataSource.database(database!))
                        .where(Expression.property("description").match("'seafront sea'"))
for row in try! hotelSearchQuery.run() {
    if let ftsRow = row as? FullTextQueryRow {
        print("hotelSearchQuery :: \(ftsRow.fullTextMatched!)")
    }
}
// any time the match operator it runs FTS and returns FullTextQueryRow

// SQLite FTS4 has special DSL like '' and * to make the search for granular
// if we talk about it since it diverges from N1Ql
