//: [Previous](@previous)
//: # N1QL queries in Couchbase Mobile 2.0
import CouchbaseLiteSwift
import PlaygroundSupport

let documentsDirectory = playgroundSharedDataDirectory
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
config.directory = documentsDirectory.path
let database = try Database(name: "travel-sample", config: config)
/*:
 - Experiment:
 Find out how many documents are in the database.
*/
for (index, row) in database.allDocuments.enumerated() {
    let string = "type \(row.string(forKey: "type"))"
}
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
    "faaQuery :: \(row.document.string(forKey: "airportname"))"
}
/*:
 ### = statement
 - If the input text is 4 characters long match on the `icao` field.
 ```
 SELECT airportname from `travel-sample` WHERE icao = UPPER('YYYY');
 ```
*/
let icaoQuery = Query
    .select()
    .from(DataSource.database(database))
    .where(Expression.property("icao").equalTo("kSfO".uppercased()))
for row in try! icaoQuery.run() {
    "icaoQuery :: \(row.document.string(forKey: "airportname"))"
}
/*:
 ### LIKE statement
 - The `like` statement can be used to match on a prefix ("match values that start with ...").
 - Case sensitive.
 ```
 SELECT airportname from `travel-sample` WHERE LOWER(airportname) LIKE LOWER('%ZZZZZ%');
 ```
*/
let startsWithQuery = Query
                        .select()
                        .from(DataSource.database(database))
                        .where(Expression.property("airportname").like("Heath%"))
for row in try! startsWithQuery.run() {
    row.document.string(forKey: "airportname")
}
/*:
 - Experiment:
 Update the above query to match rows that begin with (only) a particular set of characters.
*/
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
let flightPathQuery = Query
                        .select()
                        .from(DataSource.database(database))
                        .where(Expression.property("sourceairport").equalTo("MCO")
                            .and(Expression.property("destinationairport").equalTo("SEA")))
for (index, row) in try flightPathQuery.run().enumerated() {
    "flightPathQuery :: \(row.document.string(forKey: "airportname"))"
}
/*:
 - Experiment:
 Modify the code above to print the schedule for each airline flying this route.
*/
/*:
 ## Ordering
 ### orderBy statement
 - By default, there is no ordering (however they get pulled from the database).
 - That's also why the query result is a `Set`.
 - If ordering is important to the app, must use the `orderBy` statement.
 - Performance vs ordering trade-off.
*/
let orderedStartsWithQuery = Query
    .select()
    .from(DataSource.database(database))
    .where(Expression.property("airportname").like("%London%"))
for (index, row) in try orderedStartsWithQuery.run().enumerated() {
    "orderedStartsWithQuery :: \(row.document.string(forKey: "airportname"))"
}
/*:
 - Experiment:
 Modify the query above to order the results by the `airportname` value.
*/
/*:
 ### REGEX statement
 - There's also a regex match for more complex matching.
 - Queries with the like operator can't be indexed.
*/
/*:
 ### Coming soon
 - Projection
 - Data aggregation (groupBy)
 - Joins
*/
