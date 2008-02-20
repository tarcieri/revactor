require 'revactor'

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
        broadcast.call "*** #{nickname} joined"
        client << T[:write, "*** Users: " + clients.values.join(', ')]
      end

      filter.when(T[:say]) do |_, client, msg|
        nickname = clients[client]
        broadcast.call "<#{nickname}> #{msg}"
      end

      filter.when(T[:disconnected]) do |_, client|
        nickname = clients.delete client
        broadcast.call "*** #{nickname} left"
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
    rescue EOFError
      puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"
    end

    unless sock.closed?
      sock.controller = Actor.current
      sock.active = :once
    
      filter = proc do |f|
        f.when(T[:write]) do |_, message|
          sock.write message
          true
        end

        f.when(T[:tcp, sock]) do |_, _, message|
          server << T[:say, Actor.current, message]
          sock.active = :once
          true
        end
    
        f.when(T[:tcp_closed, sock]) do
          puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"
          server << T[:disconnected, Actor.current]
          false
        end
      end
    
      while Actor.receive(&filter); end
    end
  end
end