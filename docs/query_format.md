# Query format
The basic query is a multipart message that consists of 2 parts: a version byte and a query object.

## version
The version byte the client sends must match the server's own version number, else the server will respond with an error.

## query
The query object is a JSON serialized object. all fields are optional, but an empty query will be considered an error.

### data types
`range`: a JSON object containing either:
- one `value` field containing the value to search for
- `min` and `max` fields containign 2 integers between which to search for. an onbounded range can be represented by using MAX_INT and MIN_INT (or whatever they are named).

`sql_like`: the SQL `LIKE` syntax:
- `_` means "one single character"
- `%` means "zero, one or more characters"

### fields
| name | type | comment | example |
|------|------|---------|---------|
| protocol | range | the protocol version to search for | {"value" : 767} |
| version | sql_like | the version name (usually contains server software) of the server | "Paper %" |
| playercount | range | the amount of players on a server | {"min": 3, "max": 5} |
| playercap | range | the amount of players the server said they can handle | {"value": 20} |
| motd | sql_like | the MOTD (message of the day) of the server. this will use the flattened representation | "A Minecraft Server" |
| enforcesSecureChat | bool | wheter or not the server enforces secure chat | false |

# Server response
the server responds to a query with another multipart message. this one contains 2 parts: an error code byte and data.

If the error code is 0, that means it was a success, and the server will put a JSON list containing the found servers (limited to 100) in the data.
Else, the data will contain a string containg an error description.

| error code | description |
|------------|-------------|
| 0 | Success |
| 1 | Version mismatch |
| 2 | Invalud Query |
