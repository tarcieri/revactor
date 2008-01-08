require File.dirname(__FILE__) + '/../revactor'
require 'rubygems'
require 'mongrel'

# Mongrel doesn't really care if we read more than Const::CHUNK_SIZE
# and readpartial doesn't really make sense in Revactor's API since
# read accomplishes the same functionality, so make readpartial call read
class Revactor::TCP::Socket
  def readpartial(value = nil)
    read
  end
end

module Mongrel
  class HttpServer
    def initialize(host, port, num_processors=950, throttle=0, timeout=60)
      @socket = Revactor::TCP.listen(host, port)
      @classifier = URIClassifier.new
      @host = host
      @port = port
      @throttle = throttle
      @num_processors = num_processors
      @timeout = timeout
    end

    # Runs the thing.  It returns the thread used so you can "join" it.  You can also
    # access the HttpServer::acceptor attribute to get the thread later.
    def run
      @acceptor = Actor.new do
        # FIXME This socket.controller crap can hopefully go away soon
        @socket.controller = Actor.current
        begin
          while true
            begin
              client = @socket.accept
              actor = Actor.new(client) { |c| client.controller = Actor.current; process_client(c) }
              actor[:started_on] = Time.now
            rescue StopServer
              break
            rescue Errno::EMFILE
              reap_dead_workers("too many open files")
              sleep 0.5
            rescue Errno::ECONNABORTED
              # client closed the socket even before accept
              client.close rescue nil
            rescue Object => e
              STDERR.puts "#{Time.now}: Unhandled listen loop exception #{e.inspect}."
              STDERR.puts e.backtrace.join("\n")
            end
          end
          graceful_shutdown
        ensure
          @socket.close
          # STDERR.puts "#{Time.now}: Closed socket."
        end
      end

      return @acceptor
    end
  end
end