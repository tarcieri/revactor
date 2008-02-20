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

loop do
  Actor.spawn(listener.accept) do |sock|
    puts "#{sock.remote_addr}:#{sock.remote_port} connected"

    begin
      sock.write "Please enter a nickname:"
      nickname = sock.read

      server << T[:register, Actor.current, nickname]
      sock.controller = Actor.current
      sock.active = :once
    
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
