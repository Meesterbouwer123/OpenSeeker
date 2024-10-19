# OpenSeeker
A ServerSeeker clone, but now open-source

## Structure
### Proposal: notcancername
1. Run `masscan`.
2. Collect results from `masscan`, in its binary format.
3. Parse its binary format according to [here](https://github.com/robertdavidgraham/masscan/blob/dfd20019c2fe06b915165324e808652ccddba723/src/in-binary.c#L472)
4. Submit the IPs to a program that does the SLP. Ideally, this should be able to be separate enough, so it can be run on a different machine if desired.
5. Do the [SLP](https://wiki.vg/Server_List_Ping). If it doesn't succeed, use the legacy ping. If that doesn't succeed, try to join in offline mode. This should be fast, so an event loop like [libxev](https://github.com/mitchellh/libxev) or [libuv](https://libuv.org/).
6. Store the information: at least timestamp, IP, port, banner, players, offline mode. Wasn't there also some kind of BungeeCord exploit? This should probably be in some kind of database, like [SQLite](https://sqlite.org) or [PostgreSQL](https://postgresql.org).
### Proposal: Meesterbouwer123
Let me overengineer this a little bit, I first need to see if the webhook works
