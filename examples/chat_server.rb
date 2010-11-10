#
# A simple chat server implemented using 1 <-> N actors 
# 1 server, N client managers, plus a listener
#
# The server handles all message formatting, traffic routing, and connection tracking
# Client managers handle connection handshaking as well as low-level network interaction
# The listener spawns new client managers for each incoming connection
#

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'revactor'

HOST = '0.0.0.0'
PORT = 4321

# Open a listen socket.  All traffic on new connections will be run through
# the "line" filter, so incoming messages are delimited by newlines.
listener = Actor::TCP.listen(HOST, PORT, :filter => :line)
puts "Listening on #{HOST}:#{PORT}"

# The ClientConenction class handles all network interaction with clients
# This includes the initial handshake (getting a nickname), processing
# incoming messages, and writing out enqueued messages
class ClientConnection
  # Add .spawn and .spawn_link methods to the singleton
  extend Actorize
  
  def initialize(dispatcher, sock)
    @dispatcher, @sock = dispatcher, sock
    puts "#{sock.remote_addr}:#{sock.remote_port} connected"
    
    handshake
    message_loop
  rescue EOFError
    puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"
    @dispatcher << T[:disconnected, Actor.current]  
  end
  
  def handshake
    @sock.write "Please enter a nickname:"
    nickname = @sock.read
    @dispatcher << T[:register, Actor.current, nickname]
  end

  def message_loop
    # Flip the socket into asynchronous "active" mode
    # This means the Actor can receive messages from
    # the socket alongside other events.
    @sock.controller = Actor.current
    @sock.active = :once

    # Main message loop
    loop do
      Actor.receive do |filter|
        # Handle incoming TCP traffic.  The line filter ensures that all
        # incoming traffic is filtered down to CRLF-delimited lines of text
        filter.when(T[:tcp, @sock]) do |_, _, message|
          @dispatcher << T[:line, Actor.current, message]
          @sock.active = :once
        end
        
        # Write a message to the client's socket
        filter.when(T[:write]) do |_, message|
          @sock.write message
        end

        # Indicates the client's connection has closed
        filter.when(T[:tcp_closed, @sock]) do
          raise EOFError
        end
      end
    end
  end
end

class Dispatcher
  extend Actorize
  
  def initialize
    @clients = {}
    run
  end
  
  def run
    loop do
      Actor.receive do |filter|
        filter.when(T[:register]) do |_, client, nickname|
          @clients[client] = nickname
          broadcast "*** #{nickname} joined"
          client << T[:write, "*** Users: " + @clients.values.join(', ')]
        end

        filter.when(T[:line]) do |_, client, msg|
          nickname = @clients[client]
          broadcast "<#{nickname}> #{msg}"
        end

        filter.when(T[:disconnected]) do |_, client|
          nickname = @clients.delete client
          broadcast "*** #{nickname} left" if nickname
        end
      end
    end
  end
  
  # Broadcast a message to all connected clients
  def broadcast(message)
    @clients.keys.each { |client| client << T[:write, message] }
  end
end

dispatcher = Dispatcher.spawn
loop { ClientConnection.spawn(dispatcher, listener.accept) }