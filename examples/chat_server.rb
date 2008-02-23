#
# A simple chat server implemented using 1 <-> N actors 
# 1 server, N client managers, plus a listener
#
# The server handles all message formatting, traffic routing, and connection tracking
# Client managers handle connection handshaking as well as low-level network interaction
# The listener spawns new client managers for each incoming connection
#

require File.dirname(__FILE__) + '/../lib/revactor'

HOST = 'localhost'
PORT = 4321

# Open a listen socket.  All traffic on new connections will be run through
# the "line" filter, so incoming messages are delimited by newlines.

listener = Actor::TCP.listen(HOST, PORT, :filter => :line)
puts "Listening on #{HOST}:#{PORT}"

# Spawn the server
server = Actor.spawn do
  clients = {}
  
  # A proc to broadcast a message to all connected clients.  If the server
  # were encapsulated into an object this could be a method
  broadcast = proc do |msg|
    clients.keys.each { |client| client << T[:write, msg] }
  end
  
  # Server's main loop.  The server handles incoming messages from the
  # client managers and dispatches them to other client managers.
  loop do 
    Actor.receive do |filter|
      filter.when(T[:register]) do |_, client, nickname|
        clients[client] = nickname
        broadcast.call "*** #{nickname} joined"
        client << T[:write, "*** Users: " + clients.values.join(', ')]
      end

      filter.when(T[:say]) do |_, client, msg|
        nickname = clients[client]
        broadcast.call "<#{nickname}> #{msg}"
      end

      filter.when(T[:disconnected]) do |_, client|
        nickname = clients.delete client
        broadcast.call "*** #{nickname} left" if nickname
      end
    end
  end
end

# The main loop handles incoming connections
loop do
  # Spawn a new actor for each incoming connection
  Actor.spawn(listener.accept) do |sock|
    puts "#{sock.remote_addr}:#{sock.remote_port} connected"

    # Connection handshaking
    begin
      sock.write "Please enter a nickname:"
      nickname = sock.read

      server << T[:register, Actor.current, nickname]
      
      # Flip the socket into asynchronous "active" mode
      # This means the Actor can receive messages from
      # the socket alongside other events.
      sock.controller = Actor.current
      sock.active = :once
    
      # Main message loop
      loop do
        Actor.receive do |filter|
          filter.when(T[:tcp, sock]) do |_, _, message|
            server << T[:say, Actor.current, message]
            sock.active = :once
          end
          
          filter.when(T[:write]) do |_, message|
            sock.write message
          end
          
          filter.when(T[:tcp_closed, sock]) do
            raise EOFError
          end
        end
      end
    rescue EOFError
      puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"
      server << T[:disconnected, Actor.current]
    end
  end
end
