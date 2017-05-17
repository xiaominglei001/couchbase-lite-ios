/*:
 # Todo Sample Data Model
 ## task-list
     {
         "_id": "dk39-4kd9-1w9d",
         "type": "task-list",
         "name": "Groceries",
         "owner": "user1"
     }
 ## task
     {
         "_id": "de30-5d54-75b4",
         "type": "task",
         "name": "Potatoes",
         "complete": false,
         "task-list": "dk39-4kd9-1w9d",
         "_attachments": {
             "image": {...}
         }
     }
 ## task-list.user
     {
         "_id": "fd23-f3fw-3s9e",
         "type": "task-list.user",
         "username": "user2",
         "taskList": {
            "id":"dk39-4kd9-1w9d",
            "owner":"user1"
         }
     }
 ## moderator
     {
         "_id": "fd23-f3fw-3s9e",
         "type": "task-list.user",
         "username": "user2",
         "taskList": {
            "id":"dk39-4kd9-1w9d",
            "owner":"user1"
         }
     }
*/
