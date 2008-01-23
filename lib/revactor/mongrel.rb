require File.dirname(__FILE__) + '/../revactor'
require 'rubygems'
require 'mongrel'

class Revactor::TCP::Socket
  # Monkeypatched readpartial routine inserted whenever Revactor's mongrel.rb
  # is loaded.  The value passed to this method is ignored, so it is not
  # fully compatible with Socket's readpartial method.
  #
  # Mongrel doesn't really care if we read more than Const::CHUNK_SIZE
  # and readpartial doesn't really make sense in Revactor's API since
  # read accomplishes the same functionality.  So, in this implementation
  # readpartial just calls read and returns whatever is available.
  def readpartial(value = nil)
    read
  end
end

module Mongrel
  # Mongrel's HttpServer, monkeypatched to run on top of Revactor and using
  # Actors for concurrency.
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

    # Runs the thing.  It returns the Actor the listener is running in.
    def run
      @acceptor = Actor.new do
        begin
          while true
            begin
              client = @socket.accept
              actor = Actor.new client, &method(:process_client)
              actor[:started_on] = Time.now
            rescue StopServer
              break
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
