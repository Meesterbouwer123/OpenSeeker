# Query format
The basic query is a multipart message that consists of 2 parts: a version byte and a query object.

## version
The version byte the client sends must match the server's own version number; otherwise, the server will respond with an error.

## query
The query object is a JSON serialized object. All fields are optional, but an empty query will be considered an error.

### data types
`range`: a JSON object containing either:
- one `value` field containing the value to search for
- `min` and `max` fields containing 2 integers between which to search for. An unbounded range can be represented by using MAX_INT and MIN_INT (or whatever they are named).

`sql_like`: the SQL `LIKE` syntax:
- `_` means "one single character"
- `%` means "zero, one or more characters"

`player`: a JSON object containing either:
- `name`: a string containing the player name
- `uuid`: a string containing the player's UUID, can be in dashed or undashed format
- both, in which case it will search for an occurrence where **both** the name and uuid match


### fields
| name | type | comment | example |
|------|------|---------|---------|
| protocol | range | the protocol version to search for | {"value" : 767} |
| version | sql_like | the version name (usually contains server software) of the server | "Paper %" |
| player_count | range | the amount of players on a server | {"min": 3, "max": 5} |
| player_cap | range | the amount of players the server said they can handle | {"value": 20} |
| motd | sql_like | the MOTD (message of the day) of the server. This will use the flattened representation | "A Minecraft Server" |
| enforces_secure_c_hat | bool | whether the server enforces secure chat | false |
| prevents_chat_reports | bool | whether the server prevents chat reports | true |
| player| player | a player to search for | {"name": "Notch"} |
| seen_since | int | timestamp (in Unix milliseconds) after which the server has to have been seen | 1731769200000 |

# Server response
The server responds to a query with another multipart message. This one contains 2 parts: an error code byte and data.

If the error code is 0, that means it was a success, and the server will put a JSON list containing the found servers (limited to 100) in the data.
Otherwise, the data will contain a string containing an error description.

| error code | description |
|------------|-------------|
| 0 | Success |
| 1 | Version mismatch |
| 2 | Invalid Query |