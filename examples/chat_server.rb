require File.dirname(__FILE__) + '/../lib/revactor'

HOST = 'localhost'
PORT = 4321

listener = Actor::TCP.listen(HOST, PORT, :filter => :line)
puts "Listening on #{HOST}:#{PORT}"

server = Actor.spawn do
  clients = {}
  broadcast = proc do |msg|
    clients.keys.each { |client| client << T[:write, msg] }
  end

  loop do
    Actor.receive do |filter|
      filter.when(T[:register]) do |_, client, nickname|
        clients[client] = nickname[0..29] # 30 char limit, nya
        client << T[:write, "*** Users: " + clients.values.join(', ')]
        broadcast.call "*** #{nickname} joined"
      end

      filter.when(T[:say]) do |_, client, msg|
        broadcast.call "<#{clients[client]}> #{msg}"
      end

      filter.when(T[:disconnected]) do |_, client|
        clients.delete client
        broadcast.call "*** #{clients[client]} left"
      end
    end
  end
end

loop do
  Actor.spawn(listener.accept) do |sock|
    puts "#{sock.remote_addr}:#{sock.remote_port} connected"
    registered = false

    begin
      sock.write "Please enter a nickname:"
      nickname = sock.read

      server << T[:register, Actor.current, nickname]
      registered = true
      sock.controller = Actor.current

      loop do
        sock.active = :once
        Actor.receive do |filter|
          filter.when(T[:write]) do |_, message|
            sock.write message
          end
 
          filter.when(T[:tcp, sock]) do |_, _, message|
            server << T[:say, Actor.current, message]
          end
        end
      end
    rescue EOFError
      puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"
      server << T[:disconnected, Actor.current] if registered
      break
    end
  end
end
