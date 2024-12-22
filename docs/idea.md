# Motivation
The motivation behind this package is to provide a super leightweight, dependency free layer that enables powerful offline first databases.
The user should be able to use their offline & online database of choice, and only needs to provide 5 simple functions to this package that will enable all the syncing.

## End Product
Once implemented, the app will work offline without internet connection indefinetly and without any latency (besides the local database latency).
If an internet connection comes back online, the app will sync to the server, sending its local changes to the server, and reading missed changes from the server.
Multiple clients (your app) can use the same account at the same time. This implementation takes care of deciding which data is correct, such that all devices end up with the same state after syncing. (Eventual consistency)

## How it works
Additionally to all the tables you set up in your app, this syncing layer needs one additional table: "messages".
In this table, each "message" will be stored. A message is a change to a field in your database. When the user changes for example a todo in your app, the syncing layer would create a message with the following arguments:

```dart
final message = Message(
    table: 'todos',
    row: 'id_of_changed_todo',
    'column': 'name',
    value: 'Some new todo name',

    /// automatically set parameters:
    hasBeenSynced: false,
    localTimestamp: now(),
    clientId: getClientId(),
    userId: getUserId(),
);
```

This message would then be added to the local 'messages' table, as well as applied to the local 'todos' table, changing the specified field.
On the next sync with your server, this message would be sent to the server, and if received successfully, 'hasBeenSynced' would be set to true in your local 'messages' table, indicating that it has been seen by the server and doesn't need to be synced again.

During syncing we not only upload all our local messages that haven't been seen by the server, we also fetch all of the messages that we have not seen from the server.

The 'messages' table on the server has two fields that help us sync only the messages that we haven't seen before:
'clientId' & 'id'.

'clientId' refers to the device that generated this message, in the case of apps usually a phone id. When we query for unseen messages, we only want messages with the 'clientId' not equal to our own, since we already know the messages we sent ourself.

'id' is an increasing integer, starting from 0, that is increasing and unique per user (ie. a composite key). It keeps track of the order in which the messages have been received by the server. This means that if a client has synced all messages until id 5000, it can store this id locally and the next time only has to read messages with id bigger than 5000.

The combination of 'clientId' and 'id' ensures that when a client syncs, it only ever downloads relevant messages from the server that have not yet been seen by the client, ensuring minimal data transfer.

Note:
'id' refers to the order in which the server has received the messages. It does not have anything to do with when the changes were actually made and which changes will 'win' the write for a field in the database. A change could happen, then the user uses the app offline for a month, and only then syncs the changes. 


