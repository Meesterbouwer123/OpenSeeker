# OpenSeeker
A ServerSeeker clone, but now open-source

## Structure
### Proposal: notcancername
1. Run `masscan`.
2. Collect results from `masscan`, in its binary format.
3. Parse its binary format according to [here](https://github.com/robertdavidgraham/masscan/blob/dfd20019c2fe06b915165324e808652ccddba723/src/in-binary.c#L472)
4. Submit the IPs to a program that does the SLP. Ideally, this should be able to be separate enough, so it can be run on a different machine if desired. How about something like [zeromq](https://zeromq.org)?
5. Do the [SLP](https://wiki.vg/Server_List_Ping). If it doesn't succeed, use the legacy ping. If that doesn't succeed, try to join in offline mode. This should be fast, so an event loop like [libxev](https://github.com/mitchellh/libxev) or [libuv](https://libuv.org/).
6. Store the information: at least timestamp, IP, port, banner, players, offline mode. Wasn't there also some kind of BungeeCord exploit? This should probably be in some kind of database, like [SQLite](https://sqlite.org) or [PostgreSQL](https://postgresql.org).
### Proposal: Meesterbouwer123
The main scanning operation consists of 3 parts: *discovery*, *pinger* and *database*.

The *discovery* is a [masscan](https://github.com/robertdavidgraham/masscan) wrapper and will search for open ports in specified IP ranges (often 0.0.0.0/0 on port 25565, but we could also add adaptive scanning in here).

The *pinger* will take the outputs from the discovery, and perform a [Server List Ping](https://wiki.vg/Server_List_Ping) on them. we could also add other features such as cracked/bungeecord checking.

The *database* will store all the results from the pinger, and will give the pinger also a list of old servers back to see if the data is still accurate. It will also give the discovery interesting ranges to scan, as a form of adaptive scanning. This is also the part where the user interfaces (discord bot, etc) will connecto to for their queries

All the connections between the parts will probably be facilitated by something like [ZeroMQ](https://zeromq.org/).
