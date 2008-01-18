require File.dirname(__FILE__) + '/../lib/revactor'

HOST = 'localhost'
PORT = 4321

Actor.start do
  listener = Revactor::TCP.listen(HOST, PORT)
  puts "Listening on #{HOST}:#{PORT}"

  loop do
    Actor.spawn(listener.accept) do |sock|
      loop do
        begin
          sock.write sock.read
        rescue EOFError
          break
        end
      end
    end
  end
end