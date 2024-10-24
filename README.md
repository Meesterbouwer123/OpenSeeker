# OpenSeeker
A ServerSeeker clone, but now open-source

## Building
Get the [latest master version](https://ziglang.org/download) of Zig. Run `zig build`.

## Structure

At its core the project consists of 3 parts:
- The manager controls the database and handles requests from clients. 
- The discovery parts will get ranges from the manager and return all the open ports they found there. They do this using [masscan](https://github.com/robertdavidgraham/masscan).
- The pinger parts will get open ports from the manager and perform protocol-specific data collection on them, for example a [Server List Ping](https://wiki.vg/Server_List_Ping). They will then send that data back to the manager for storing it in the database.

All of thse will be connected using [ZeroMQ](https://zeromq.org/).

![diagram of how the whole pipeline works](./arch.svg)


## Implementation
Right now there is a basic manager to set up the database, and a lot of unused files for the other parts XD.

Building/running this on windows is currently not supported, try using WSL instead.

## Proposals
None yet, add something here if you have a cool idea.
