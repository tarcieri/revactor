#--
# Copyright (C)2009 Eric Wong
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Revactor
  # The UNIX module holds all Revactor functionality related to the
  # UNIX domain sockets, including drop-in replacements
  # for Ruby UNIX Sockets which can operate concurrently using Actors.
  module UNIX
    # Number of seconds to wait for a connection
    CONNECT_TIMEOUT = 10

    # Raised when a connection to a server fails
    class ConnectError < StandardError; end

    # Connect to the specified path for a UNIX domain socket
    # Accepts the following options:
    #
    #   :active - Controls how data is read from the socket.  See the
    #             documentation for Revactor::UNIX::Socket#active=
    #
    def self.connect(path, options = {})
      socket = begin
        Socket.connect path, options
      rescue SystemCallError
        raise ConnectError, "connection refused"
      end
      socket.attach Rev::Loop.default
    end

    # Listen on the specified path.  Accepts the following options:
    #
    #   :active - Default active setting for new connections.  See the
    #             documentation Rev::UNIX::Socket#active= for more info
    #
    #   :controller - The controlling actor, default Actor.current
    #
    #   :filter - An symbol/class or array of symbols/classes which implement
    #             #encode and #decode methods to transform data sent and
    #             received data respectively via Revactor::UNIX::Socket.
    #             See the "Filters" section in the README for more information
    #
    def self.listen(path, options = {})
      Listener.new(path, options).attach(Rev::Loop.default).disable
    end

    # UNIX socket class, returned by Revactor::UNIX.connect and
    # Revactor::UNIX::Listener#accept
    class Socket < Rev::UNIXSocket
      attr_reader :controller

      class << self
        # Connect to the specified path. Accepts the following options:
        #
        #   :active - Controls how data is read from the socket.  See the
        #             documentation for #active=
        #
        #   :controller - The controlling actor, default Actor.current
        #
        #   :filter - An symbol/class or array of symbols/classes which
        #             implement #encode and #decode methods to transform
        #             data sent and received data respectively via
        #             Revactor::UNIX::Socket. See the "Filters" section
        #             in the README for more information
        #
        def connect(path, options = {})
          options[:active]     ||= false
          options[:controller] ||= Actor.current

          super.instance_eval {
            @active, @controller = options[:active], options[:controller]
            @filterset = [*initialize_filter(options[:filter])]
            self
          }
        end
      end

      def initialize(socket, options = {})
        super(socket)

        @active ||= options[:active] || false
        @controller ||= options[:controller] || Actor.current
        @filterset ||= [*initialize_filter(options[:filter])]

        @receiver = @controller
        @read_buffer = IO::Buffer.new
      end

      def inspect
        "#<#{self.class}:0x#{object_id.to_s(16)} #@address_family:#@path"
      end

      # Enable or disable active mode data reception.  State can be any
      # of the following:
      #
      #   true - All received data is sent to the controlling actor
      #   false - Receiving data is disabled
      #   :once - A single message will be sent to the controlling actor
      #           then active mode will be disabled
      #
      def active=(state)
        unless @receiver == @controller
          raise "cannot change active state during a synchronous call"
        end

        unless [true, false, :once].include? state
          raise ArgumentError, "must be true, false, or :once"
        end

        if [true, :once].include?(state)
          unless @read_buffer.empty?
            @receiver << [:unix, self, @read_buffer.read]
            return if state == :once
          end

          enable unless enabled?
        end

        @active = state
      end

      # Is the socket in active mode?
      def active?; @active; end

      # Set the controlling actor
      def controller=(controller)
        Actor === controller or
          raise ArgumentError, "controller must be an actor"

        @receiver = controller if @receiver == @controller
        @controller = controller
      end

      # Read data from the socket synchronously.  If a length is specified
      # then the call blocks until the given length has been read.  Otherwise
      # the call blocks until it receives any data.
      def read(length = nil)
        # Only one synchronous call allowed at a time
        @receiver == @controller or
          raise "already being called synchronously"

        unless @read_buffer.empty? or (length and @read_buffer.size < length)
          return @read_buffer.read(length)
        end

        active = @active
        @active = :once
        @receiver = Actor.current
        enable unless enabled?

        loop do
          Actor.receive do |filter|
            filter.when(T[:unix, self]) do |_, _, data|
              if length.nil?
                @receiver = @controller
                @active = active
                enable if @active

                return data
              end

              @read_buffer << data

              if @read_buffer.size >= length
                @receiver = @controller
                @active = active
                enable if @active

                return @read_buffer.read(length)
              end
            end

            filter.when(T[:unix_closed, self]) do
              unless @receiver == @controller
                @receiver = @controller
                @receiver << T[:unix_closed, self]
              end

              raise EOFError, "connection closed"
            end
          end
        end
      end

      # Write data to the socket.  The call blocks until all data has been
      # written.
      def write(data)
        # Only one synchronous call allowed at a time
        @receiver == @controller or
          raise "already being called synchronously"

        active = @active
        @active = false
        @receiver = Actor.current
        disable if @active

        super(encode(data))

        Actor.receive do |filter|
          filter.when(T[:unix_write_complete, self]) do
            @receiver = @controller
            @active = active
            enable if @active and not enabled?

            return data.size
          end

          filter.when(T[:unix_closed, self]) do
            @active = false
            raise EOFError, "connection closed"
          end
        end
      end

      alias_method :<<, :write

      #########
      protected
      #########

      #
      # Filter setup
      #

      # Initialize filters
      def initialize_filter(filter)
        case filter
        when NilClass
          []
        when Tuple
          name, *args = filter
          case name
          when Class
            name.new(*args)
          when Symbol
            symbol_to_filter(name).new(*args)
          else raise ArgumentError, "unrecognized filter type: #{name.class}"
          end
        when Array
          filter.map { |f| initialize_filter f }
        when Class
          filter.new
        when Symbol
          symbol_to_filter(filter).new
        end
      end

      # Lookup filters referenced as symbols
      def symbol_to_filter(filter)
        case filter
        when :line then Revactor::Filter::Line
        when :packet then Revactor::Filter::Packet
        else raise ArgumentError, "unrecognized filter type: #{filter}"
        end
      end

      # Decode data through the filter chain
      def decode(data)
        @filterset.inject([data]) do |a, filter|
          a.inject([]) do |a2, d|
            a2 + filter.decode(d)
          end
        end
      end

      # Encode data through the filter chain
      def encode(message)
        @filterset.reverse.inject(message) { |m, filter| filter.encode(*m) }
      end

      #
      # Rev::UNIXSocket callback
      #

      def on_connect
        @receiver << T[:unix_connected, self]
      end

      def on_connect_failed
        @receiver << T[:unix_connect_failed, self]
      end

      def on_close
        @receiver << T[:unix_closed, self]
      end

      def on_read(data)
        # Run incoming message through the filter chain
        message = decode(data)

        if message.is_a?(Array) and not message.empty?
          message.each { |msg| @receiver << T[:unix, self, msg] }
        elsif message and not message.empty?
          @receiver << T[:unix, self, message]
        else return
        end

        if @active == :once
          @active = false
          disable
        end
      end

      def on_write_complete
        @receiver << T[:unix_write_complete, self]
      end
    end

    # UNIX Listener returned from Revactor::UNIX.listen
    class Listener < Rev::UNIXListener
      attr_reader :controller

      # Listen on the specified path.  Accepts the following options:
      #
      #   :active - Default active setting for new connections.  See the
      #             documentation Rev::UNIX::Socket#active= for more info
      #
      #   :controller - The controlling actor, default Actor.current
      #
      #   :filter - An symbol/class or array of symbols/classes which implement
      #             #encode and #decode methods to transform data sent and
      #             received data respectively via Revactor::UNIX::Socket.
      #             See the "Filters" section in the README for more information
      #
      def initialize(path, options = {})
        super(path)
        opts = {
          :active     => false,
          :controller => Actor.current
        }.merge(options)

        @active, @controller = opts[:active], opts[:controller]
        @filterset = options[:filter]

        @accepting = false
      end

      def inspect
        "#<#{self.class}:0x#{object_id.to_s(16)}>"
      end

      # Change the default active setting for newly accepted connections
      def active=(state)
        unless [true, false, :once].include? state
          raise ArgumentError, "must be true, false, or :once"
        end

        @active = state
      end

      # Will newly accepted connections be active?
      def active?; @active; end

      # Change the default controller for newly accepted connections
      def controller=(controller)
        Actor === controller or
          raise ArgumentError, "controller must be an actor"
        @controller = controller
      end

      # Accept an incoming connection
      def accept
        raise "another actor is already accepting" if @accepting

        @accepting = true
        @receiver = Actor.current
        enable

        Actor.receive do |filter|
          filter.when(T[:unix_connection, self]) do |_, _, sock|
            @accepting = false
            return sock
          end
        end
      end

      #########
      protected
      #########

      #
      # Rev::UNIXListener callbacks
      #

      def on_connection(socket)
        sock = Socket.new(socket,
          :controller => @controller,
          :active => @active,
          :filter => @filterset
        )
        sock.attach(evloop)

        @receiver << T[:unix_connection, self, sock]
        disable
      end
    end
  end
end
