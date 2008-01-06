require File.dirname(__FILE__) + '/../lib/revactor'

HOST = 'localhost'
PORT = 4321

RESPONDER = proc { |sock|
  sock.controller = Actor.current

  loop do
    begin
      sock.write sock.read
    rescue EOFError
      break
    end
  end
}

Actor.start do
  listener = Revactor::TCP.listen(HOST, PORT)
  puts "Listening on #{HOST}:#{PORT}"

  loop { Actor.spawn(listener.accept, &RESPONDER) }
end
