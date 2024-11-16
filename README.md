# OpenSeeker
A ServerSeeker clone, but now open-source. This is a work in progress.

Join [Discord](https://discord.gg/k5GvCMaDgN) to chat.

## Timeline
We hope to complete the basic functionality until end of year: [Basic release](https://github.com/Meesterbouwer123/OpenSeeker/milestone/1)

## Building
Get the [latest master version](https://ziglang.org/download) of Zig. Run `zig build`.

## Structure
At its core the project consists of 3 parts:
- The manager controls the database and handles requests from clients.
- The discovery parts will get ranges from the manager and return all the open ports they found there. They do this using [masscan](https://github.com/robertdavidgraham/masscan).
- The pinger parts will get open ports from the manager and perform protocol-specific data collection on them, for example a [Server List Ping](https://wiki.vg/Server_List_Ping). They will then send that data back to the manager for storing it in the database.

All of thse are connected using [ZeroMQ](https://zeromq.org/).

![diagram of how the whole pipeline works](./arch.svg)

## Protocol documentation
Will be in `docs/`.

## Proposals
Open an issue to propose functionality!
