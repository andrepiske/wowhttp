## What is this?

I'm making an HTTP(S) server from scratch just for fun.

This is an experiment, the code base changes a lot. There are no tests.

## Features

- HTTP 1.1 and HTTP/2 server
- Writes and reads are all asynchronous
- Thread-safe
- TLS 1.2 support
- Streaming responses

## Roadmap

- Refactor code to create adapters
- Create rack adapter
- Create reverse-proxy adapter
- Make "gears" thread-safe
- Get it working with jruby and real threads
- Write tests
- Support TLS 1.3
- Support for Websockets
- Support for let's encrypt ACME protocol
- Have a decent logging mechanism

## Setup & run

This likely won't work out of the box because some files are missing and some SSL certificate setup is needed.

Make sure you `$ bundle install` before running.

`cd` to the `some_code` folder then open the server:
```shell
$ cd some_code
$ ../bin/appmaker main.rb
```

Then navigate to http://localhost:3999/
