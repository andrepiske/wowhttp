## What is this?

I'm making an HTTP(S) server from scratch mostly for fun.

**This is an experiment**, the code base changes a lot. There are no tests although I'm currently running against [h2spec](https://github.com/summerwind/h2spec).

## Features

- HTTP 1.1 and HTTP/2 server
- Writes and reads are all asynchronous
- Thread-safe
- TLS 1.2 support
- Streaming responses
- Compatibility with Rack through an adapter

## Roadmap

Currently being worked on:

- Make it pass all specs of [h2spec](https://github.com/summerwind/h2spec)

Next steps, from top priority to lesser:

- Make "gears" closeable
- Make "gears" thread-safe 
- Write some docs
- Create reverse-proxy adapter
- Refactor code to create adapters
- Get it working with jruby and real threads
- Have a decent logging mechanism
- Write unit tests
- Support TLS 1.3
- Support for Websockets
- Support for let's encrypt ACME protocol

## Setup & run

Don't, it's an experiment. Or, read the code and figure it out yourself :)

