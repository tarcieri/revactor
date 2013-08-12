Revactor
========

### NOTE: Revactor is defunct and broken. It's only being kept available for historical interest.
### Please check out [Celluloid](http://celluloid.io), the new hotness for Ruby actors instead!

Revactor is an Actor model implementation for Ruby 1.9 built on top of the
[Rev](http://github.com/tarcieri/rev) event library. Revactor is well suited
for developing I/O-heavy asynchronous applications that handle large numbers
of concurrent network connections. Its design is largely modeled off of Erlang.

You can load Revactor in your Ruby 1.9 application with:

    require 'revactor'

If you'd like to learn more about the Actor model, more information is
available on the Revactor web site:

[http://revactor.github.io/philosophy](http://revactor.github.io/philosophy)

Anatomy
-------

Revactor is built out of several parts which interoperate to let you build
network servers painlessly while still guaranteeing correct operation:

* Actors: Actors are the main concurrency primitive used by Revactor.

* Revactor::TCP: This module provides an API duck typed to the Ruby
  Sockets API.  However, rather than blocking calls actually blocking,
  they defer to the underlying event loop.  Actor-focused means of
  receiving data are also provided.

* Filters: Applied to all incoming data directly when it's received, Filters
  can preprocess or postprocess data before it's even delivered to an Actor.
  This is useful for handling protocol framing or other streaming transforms.

Actors
------

Actors are lightweight concurrency primitives which communicate using message
passing.  They multitask cooperatively, meaning that many of the worries 
surrounding threaded programming disappear.  Any sequence of operations you do 
in an Actor are executed in the order you specify.  You don't (generally) have 
to worry about another Actor doing something in the background as you frob a 
particular data structure.

Actors are created by calling Actor.spawn:

    myactor = Actor.spawn { puts "I'm an Actor!" }

When you spawn an Actor it's scheduled to run after the current Actor either
completes or calls Actor.receive.  Speaking of which, Actor.receive is used
to receive messages:

    myactor = Actor.spawn do
      Actor.receive do |filter|
        filter.when(:dog) { puts "I got a dog!" }
      end
    end

You can send a message to an actor using its #send method or <<

Calling: 

    myactor << :dog

prints:

    "Yay, I got a dog!"

You can retrieve the current Actor by calling Actor.current.  There will always 
be a default Actor available for every Thread.

Mailboxes
---------

Actors can receive messages, but where do those messages go?  The answer
is every Actor has a mailbox.  The mailbox is sort of like a message queue,
but you don't have to read it sequentially.  You can apply filters to it, and
change the filter set at any time.

When you call Actor.receive, it yields a filter object and lets you register
message patterns you're interested in, then it sleeps and waits for messages.
Each time the current actor receives a message, it's scanned by the filter,
and if a match occurs the appropriate action is given.

Matching is performed by the Filter#when method, which takes a pattern to match
against a message and a block to call if the message matches.  The pattern is
compared to the message using ===, the same thing Ruby uses for case statements.
You can think of the filter as a big case statement.

Like the case statement, a class matches any objects of that class.  Since all 
classes descend from Object passing Object will match all messages.  You can
also pass a regexp to match against a string.

Revactor installs the Case gem by default.  This is useful for matching against
messages stored in Arrays, or in fixed-size arrays called Tuples.  Case can
be used as follows:

    filter.when(Case[:foobar, Object, Object]) { ... }

This will look for messages which are Arrays or Tuples with three members,
whose first member is the symbol :foobar.  As you can probably guess, Case[]
matches against an Array or Tuple with the same number of members, and
matches each member of the given tuple with ===.  Once again, Object is a 
wildcard, so the other members of the message can be anything.

Want more complex pattern matching?  Case lets you use a block to match any
member by using a guard, ala:

    filter.when(Case[:foobar, Case.guard { |n| n > 100 }, Object]) { ... }

This will look for an Array / Tuple with three members, whose first member is
the symbol :foobar and whose second member is greater than 100.

You can also specify how long you wish to wait for a message before timing out.
This is accomplished with Filter#after:

    filter.after(0.5) { raise 'it timed out ;_;' }

The #after method takes a duration in seconds to wait (in the above example it
waits a half second) before the receive operation times out.

Actor.receive returns whatever value the evaluated action returned.  This means
you don't have to depend on side effects to extract values from receive, 
instead you can just interpret its return value.

Handling Exceptions
-------------------

In a concurrent environment, dealing with exceptions can be incredibly 
confusing.  By default, any unhandled exceptions in an Actor are logged
and any remaining Actors continue their normal operation.  However, Actors
also provide a powerful tool for implementing fault-tolerant systems that
can gracefully recover from exceptions.

Actors can be linked to each other:  

    another_actor = Actor.spawn { puts "I'm an Actor!" }
    Actor.link(another_actor)

This can also be done as a single "atomic" operation:

    actor = Actor.spawn_link { puts "I'm an Actor!" }

When Actors are linked, any exceptions which occur in one will be raised in the 
other, and vice versa.  This means if one Actor dies, any Actors it's linked to 
will also die.  Furthermore, any Actors those are linked to also die.  This 
occurs until the entire graph of linked Actors has been walked.

In this way, you can organize Actors into large groups which all die 
simultaneously whenever an error occurs in one.  This means that if an error
occurs and one Actor dies, you're not left with an interdependent network of
Actors which are in an inconsistent state.  You can kill off the whole group
and start over fresh.

But if an Actor crashing kills off every Actor it's linked to, what Actor will
be left to restart the whole group?  The answer is that an Actor can trap
exit events from another and receive them as messages:

    Actor.current.trap_exit = true
    actor = Actor.spawn_link { puts "I'm an Actor!" }
    Actor.receive do |filter|
      filter.when(Case[:exit, actor, Object]) { |msg| p msg }
    end

will print something to the effect of:

    I'm an Actor!
    [:exit, #<Actor:0x54ad6c>, nil]

We were sent a message in the form:

    [:exit, actor, reason]

and in this case reason was nil, which informs us the Actor exited normally.
But what if it dies due to an exception instead?

    Actor.current.trap_exit = true
    actor = Actor.spawn_link { raise "I fail!" }
    Actor.receive do |filter|
      filter.when(Case[:exit, actor, Object]) { |msg| p msg }
    end

We now get the entire exception, captured and delivered as a message:

    [:exit, #<Actor:0x53ec24>, #<RuntimeError: I fail!>]

If the Actor that died were linked to any others which were not trapping exits,
those would all die and the ones trapping exits would remain.  This allows us
to implement supervisors which trap exits and respond to exit messages.  The
supervisor's job is to start an Actor initially, and if it fails log the error
then restart it.

In this way Actors can be used to build complex concurrent systems which fail
gracefully and can respond to errors by restarting interdependent components
of the system en masse.

Revactor::TCP
-------------

The TCP module lets you perform TCP operations on top of the Actor model.  For
those of you familiar with Erlang, it implements something akin to gen_tcp.
Everyone else, read on!

Perhaps the best part of Revactor::TCP is you don't really need to know 
anything about the Actor model to use it.  For the most part it's duck typed
to the Ruby Socket API and can operate as a drop-in replacement.

To make an outgoing connection, call:

    sock = Revactor::TCP.connect(host, port)

This will resolve the hostname for host (if it's not an IPv4 or IPv6 address),
make the connection, and return a socket to it.  The best part is: this call
will "block" until the connection is established, and raise exceptions if the
connection fails.  It works just like the Sockets API.

However, it's not actually blocking.  Underneath this call is using the
Actor.receive method to wait for events.  This means other Actors can run in
the background while the current one is waiting for a connection.

Furthermore, the Actor making this call can receive other events and they
will remain undisturbed in the mailbox.  The connect method filters for
messages specifically related to making an outgoing connection.

To listen for incoming connections, there's a complimentary method:

    listener = Revactor::TCP.listen(addr, port)

This will listen for incoming connections on the given address and port.  It
returns a listen socket with a #accept method:

    sock = listener.accept

Like TCP.connect, this method will block waiting for connections, but in
actuality is calling Actor.receive waiting for messages related to incoming
connections.

Now that you have a handle on a Revactor TCP socket, there's several ways you
can begin using it.  The first is using a standard imperative sockets API:

    data = sock.read(1024)

This call will "block" until it reads a kilobyte from the socket.  However,
you may not be interested in a specific amount of data, just whenever data
is available on the socket.  In that case, you can just call the #read method
without any argument:

    data = sock.read

There's also a corresponding command to write to the socket.  Like read this
command will also "block" until all data has been written out to the socket:

    sock.write data

For Actors that want to deal with both incoming TCP data and messages from
other Actors, Revactor's TCP sockets also support an approach called
active mode.  Active mode automatically delivers incoming data as a message
to what's known as the Socket's controller.  You can assign the Socket's
controller whenever you want:

    sock.controller = Actor.current

Once you've done this, you can turn on active mode to begin receiving messages:

    sock.active = true
    Actor.receive do |filter|
      filter.when(Case[:tcp, sock, Object]) do |_, _, data|
        ...
      end

      filter.when(Case[:somethingelse, Object]) do |_, message|
        ...
      end
    end

(note: _ is an idiom which means ignore/discard a variable)

With active mode, the controller will receive all data as quickly as it can be
read off the socket.  If the Actor processing incoming message can't process
them as quickly as they're being read, then they'll begin piling up in the
mailbox until the controller is able to catch up (if ever).

In order to prevent this from happening, sockets can be set active once:

    sock.active = :once

This means read the next incoming message, then fall back to active = false.
The underlying system will stop monitoring the socket for incoming data,
and you're free to spend as much time as you'd like handling it.  Once
you're ready for the next message, just set active to :once again.

Filters
-------

Not to be confused with Mailbox filters, Revactor's TCP sockets can each have
a filter chain.  Filters are specified when a connection is created:

    sock = Revactor::TCP.connect('irc.efnet.org', 6667, :filter => :line)

Filters transform data as it's read or written off the wire.  In this case
we're connecting to an IRC server, and the IRC protocol is framed using a
newline delimiter.

The line filter will scan incoming messages for a newline, and buffer until
it encounters one.  When it finds one, it will reassemble the entire message
from the buffer and deliver it to you in one fell swoop.

With the line filter on, receiving messages off IRC is easy:

    message = sock.read

This will provide you with the entire next message, with the newline delimiter
already removed.

If the filter name is a symbol, Revactor will look under its filters directory
for a class of the cooresponding name.  Alternatively you can pass the name of
a class you created yourself which responds to the methods encode and decode:

    sock = Revactor::TCP.connect(host, port, :filter => MyFilter)

Filter chains can be specified by passing an array:

    sock = Revactor::TCP.connect(host, port, :filter => [MyFilter, :line])

You can pass arguments to your filter's initialize method by passing an array
with a class name as a member of a filter chain:

    sock = Revactor::TCP.connect(host, port, :filter => [[Myfilter, 42], :line])

In addition to the line filter, Revactor bundles a :packet filter.  This filter
constructs messages with a length prefix that specifies the size of the
remaining message.  This is a simple and straightforward way to frame
discrete messages on top of a streaming protocol like TCP.
