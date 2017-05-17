//: [Previous](@previous)
//: # N1QL queries in Couchbase Mobile 2.0
import CouchbaseLiteSwift
import PlaygroundSupport
let documentsDirectory = playgroundSharedDataDirectory
/*:
 ## Pre-existing database
 - Database with the same data as the travel sample data.
 - Replicated to a 1.x instance.
 - Opened with 2.0 (automatically upgraded).
*/
var options = DatabaseOptions()
options.directory = documentsDirectory.path
let database = try Database(name: "travel-sample", options: options)
for (index, row) in database.allDocuments.enumerated() {
    print(row)
}
/*:
 - Experiment:
 Find out how many documents are in the database.
*/

/*:
 ## Airport Query
 ### = statement
 - If the input text is 3 characters long match on the `faa` property.
 ```
 SELECT airportname from `travel-sample` WHERE faa = UPPER('XXX');
 ```
*/
let faaQuery = Query
    .select()
    .from(DataSource.database(database))
    .where(Expression.property("faa").equalTo("SfO".uppercased()))
for row in try! faaQuery.run() {
//    print("faaQuery :: \(row.document.properties!["airportname"]!)")
}
/*:
 - Note:
 Notice that the `geo` dictionary is logged as a `Subdocument`.
*/
/*:
 ### = statement
 - If the input text is 4 characters long match on the `icao` field.
 ```
 SELECT airportname from `travel-sample` WHERE icao = UPPER('YYYY');
 ```
*/
//let icaoQuery: Query
/*:
 - Experiment:
 Write the query equivalent to the N1QL statement above for Boston (icao: **KBOS**).
 ### LIKE statement
 - The `like` statement can be used to match on a prefix ("match values that start with ...").
 ```
 SELECT airportname from `travel-sample` WHERE LOWER(airportname) LIKE LOWER('%ZZZZZ%');
 ```
*/
let startsWithQuery = Query
                        .select()
                        .from(DataSource.database(database!))
                        .where(Expression.property("airportname").like("%Heath%"))
for row in try! startsWithQuery.run() {
    print("startsWithQuery :: \(row.document.properties!["airportname"]!)")
}
/*:
 - Note:
 What is the granularity of results? Is it adjustable?
*/
// case insensitive
// best reference on this is the SQLite documentation (same as N1QL)
// there's also a regex match for more complex matching
// queries with the like operator can't be indexed. -> FTS
// regex to match on uppercase only prefix
/*:
 ## FlightPath Query
 ### AND statement
 ```
 SELECT a.name, s.flight, s.utc, r.sourceairport, r.destinationairport, r.equipment
 FROM `travel-sample` AS r
 UNNEST r.schedule AS s
 JOIN `travel-sample` AS a ON KEYS r.airlineid
 WHERE r.sourceairport = '{fromAirport}'
 AND r.destinationairport = '{toAirport}'
 AND s.day = {dayOfWeek}
 ORDER BY a.name ASC;
 ```
*/
//let flightPathQuery = Query
//                        .select()
//                        .from(DataSource.database(database!))
//                        .where(Expression.property("sourceairport").equalTo("MCO")
//                            .and(Expression.property("destinationairport").equalTo("SEA")))
//for row in try! flightPathQuery.run() {
////    print("flightPathQuery :: \(row.document.properties!["airline"]!)")
//}
//// JOINS will be in a future DB
// alternative currently
// with CBL, data can't be unested in the current DB. (not sure if it will be in the future)
/*:
 - Experiment:
 Modify the code above to print the schedule for each airline flying this route.
*/

/*:
 ## Ordering
 ### orderBy statement
 - By default, the results are ordered in lexicographic order of the document ID property.
 - The `orderBy` method can be used on a query to specify the ordering of results.
*/
// by default there's no ordering. they come out in whatever way SQLite pulled them from the database. may change accross app runs so if ordering is important to the app then must use the orderBy. that's why it's called a set because there's no ordering guaranteed. perfomance vs ordering is trade-off

//let orderedStartsWithQuery = Query
//    .select()
//    .from(DataSource.database(database!))
//    .where(Expression.property("airportname").like("%London%"))
//for row in try! orderedStartsWithQuery.run() {
////    print("orderedStartsWithQuery :: \(row.document.properties!["airportname"]!)")
//}
/*:
 - Experiment:
 Modify the query above to order the results by the `airportname` value.
*/
/*:
 ## Data aggregation
 - Is this supported in the cross platform Query API?
*/
//let routesQuery = Query
//                    .select()
//                    .from(DataSource.database(database!))
//                    .where(Expression.property("type").equalTo("route"))
// Todo
/*:
 - Note:
 Is this feature currently available in the cross-platform API.
*/