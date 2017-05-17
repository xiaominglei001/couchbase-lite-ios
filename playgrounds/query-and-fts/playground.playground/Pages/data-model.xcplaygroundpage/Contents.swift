/*:
 # Travel Sample Data Model
 ## airline
     {
      "id": 24,
      "type": "airline",
      "name": "American Airlines",
      "iata": "AA",
      "icao": "AAL",
      "callsign": "AMERICAN",
      "country": "United States"
     }
 ## airport
     {
         "id": 6903,
         "type": "airport",
         "airportname": "Waukesha County Airport",
         "city": "Waukesha",
         "country": "United States",
         "faa": "UES",
         "icao": null,
         "tz": "America/Chicago",
         "geo": {
             "lat": 43.0410278,
             "lon": -88.2370556,
             "alt": 911
         }
     }
 ## route
     {
         "id": 5966,
         "type": "route",
         "airline": "AA",
         "airlineid": "airline_24",
         "sourceairport": "MCO",
         "destinationairport": "SEA",
         "stops": 0,
         "equipment": "737",
         "schedule": [
             {
                 "day": 0,
                 "utc": "04:02:00",
                 "flight": "AA461"
             },
             {
                 "day": 1,
                 "utc": "20:30:00",
                 "flight": "AA055"
             }
         ],
         "distance": 4104.709519888021
     }
 ## hotel
     {
         "title": "Gillingham (Kent)",
         "name": "Medway Youth Hostel",
         "address": "Capstone Road, ME7 3JE",
         "directions": null,
         "phone": "+44 870 770 5964",
         "tollfree": null,
         "email": null,
         "fax": null,
         "url": "http://www.yha.org.uk",
         "checkin": null,
         "checkout": null,
         "price": null,
         "geo": {
             "lat": 51.35785,
             "lon": 0.55818,
             "accuracy": "RANGE_INTERPOLATED"
         },
         "type": "hotel",
         "id": 10025,
         "country": "United Kingdom",
         "city": "Medway",
         "state": null,
         "reviews": [
             {
                 "content": "Thi...jor.",
                 "ratings": {
                 "Service": 5,
                 "Cleanliness": 5,
                 "Overall": 4,
                 "Value": 4,
                 "Location": 4,
                 "Rooms": 3
             },
                 "author": "Ozella Sipes",
                 "date": "2013-06-22 18:33:50 +0300"
             }
         ],
         "public_likes": [
             "Julius Tromp I",
             "Corrine Hilll"
         ],
         "vacancy": true,
         "description": "40 b...ting.",
         "alias": null,
         "pets_ok": true,
         "free_breakfast": true,
         "free_internet": false,
         "free_parking": true
     }
*/
//: [Next](@next)
