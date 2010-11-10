# An example echo server, written using Revactor::TCP
# This implementation creates a new actor for each
# incoming connection.

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'revactor'

HOST = '0.0.0.0'
PORT = 4321

# Create a new listener socket on the given host and port
listener = Revactor::TCP.listen(HOST, PORT)
puts "Listening on #{HOST}:#{PORT}"

# Begin receiving connections
loop do
  # Accept an incoming connection and start a new Actor
  # to handle it
  Actor.spawn(listener.accept) do |sock|
    puts "#{sock.remote_addr}:#{sock.remote_port} connected"

    # Begin echoing received data
    loop do
      begin
        # Write everything we read
        sock.write sock.read
      rescue EOFError
        puts "#{sock.remote_addr}:#{sock.remote_port} disconnected"

        # Break (and exit the current actor) if the connection
        # is closed, just like with a normal Ruby socket
        break
      end
    end
  end
end
