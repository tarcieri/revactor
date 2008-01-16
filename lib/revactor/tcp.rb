#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

module Revactor
  # The TCP module holds all Revactor functionality related to the
  # Transmission Control Protocol, including drop-in replacements
  # for Ruby TCP Sockets which can operate concurrently using Actors.
  module TCP
    # Number of seconds to wait for a connection
    CONNECT_TIMEOUT = 10

    class ConnectError < StandardError; end
    class ResolveError < ConnectError; end
    
    # Connect to the specified host and port.  Host may be a domain name
    # or IP address.  Accepts the following options:
    #
    #   :active - Controls how data is read from the socket.  See the
    #             documentation for #active=
    #
    def self.connect(host, port, options = {})
      socket = Socket.connect host, port, options
      socket.attach Rev::Loop.default

      Actor.receive do |filter|
        filter.when(Case[Object, socket]) do |message|
          case message[0]
          when :tcp_connected
            return socket
          when :tcp_connect_failed
            raise ConnectError, "connection refused"
          when :tcp_resolve_failed
            raise ResolveError, "couldn't resolve #{host}"
          else raise "unexpected message for #{socket.inspect}: #{message.first}"
          end              
        end

        filter.after(CONNECT_TIMEOUT) do
          raise ConnectError, "connection timed out"
        end
      end
    end
    
    # Listen on the specified address and port.  Accepts the following options:
    #
    #   :active - Controls how connections are accepted from the socket.  
    #             See the documentation for #active=
    #
    #   :controller - The controlling actor, default Actor.current
    #
    def self.listen(addr, port, options = {})
      Listener.new(addr, port, options).attach(Rev::Loop.default).disable
    end

    # TCP socket class, returned by Revactor::TCP.connect and 
    # Revactor::TCP::Listener#accept
    class Socket < Rev::TCPSocket
      attr_reader :active
      attr_reader :controller

      class << self
        # Connect to the specified host and port.  Host may be a domain name
        # or IP address.  Accepts the following options:
        #
        #   :active - Controls how data is read from the socket.  See the
        #             documentation for #active=
        #
        #   :controller - The controlling actor, default Actor.current
        #
        #   :filter - An symbol/class or array of symbols/classes which implement 
        #             #encode and #decode methods to transform data sent and 
        #             received data respectively via Revactor::TCP::Socket.
        #
        def connect(host, port, options = {})
          options[:active]     ||= false
          options[:controller] ||= Actor.current
        
          super(host, port, options).instance_eval {
            @active, @controller = options[:active], options[:controller]
            @filterset = initialize_filter(*options[:filter])
            self
          }
        end
      end
      
      def initialize(socket, options = {})        
        super(socket)
        
        @active ||= options[:active] || false
        @controller ||= options[:controller] || Actor.current
        @filterset ||= initialize_filter(*options[:filter])
        
        @receiver = @controller
        @read_buffer = Rev::Buffer.new
      end
      
      # Enable or disable active mode data reception.  State can be any
      # of the following:
      #
      #   true - All received data is sent to the controlling actor
      #   false - Receiving data is disabled
      #   :once - A single message will be sent to the controlling actor
      #           then active mode will be disabled
      def active=(state)
        unless @receiver == @controller
          raise "cannot change active state during a synchronous call" 
        end
        
        unless [true, false, :once].include? state
          raise ArgumentError, "must be true, false, or :once" 
        end
        
        if [true, :once].include?(state)
          unless @read_buffer.empty?
            @receiver << [:tcp, self, @read_buffer.read]
            return if state == :once
          end
          
          enable unless enabled?
        end
        
        @active = state
      end
      
      # Set the controlling actor
      def controller=(controller)
        raise ArgumentError, "controller must be an actor" unless controller.is_a? Actor
        
        @receiver = controller if @receiver == @controller
        @controller = controller
      end
      
      # Read data from the socket synchronously.  If a length is specified
      # then the call blocks until the given length has been read.  Otherwise
      # the call blocks until it receives any data.
      def read(length = nil)
        # Only one synchronous call allowed at a time
        raise "already being called synchronously" unless @receiver == @controller
        
        unless @read_buffer.empty? or (length and @read_buffer.size < length)
          return @read_buffer.read(length) 
        end
        
        active = @active
        @active = :once
        @receiver = Actor.current
        enable unless enabled?
        
        loop do
          Actor.receive do |filter|
            filter.when(Case[:tcp, self, Object]) do |_, _, data|
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
            
            filter.when(Case[:tcp_closed, self]) do
              unless @receiver == @controller
                @receiver = @controller
                @receiver << T[:tcp_closed, self]
              end
              
              raise EOFError, "connection closed"
            end
          end
        end
      end
      
      # Write data to the socket.  The call blocks until all data has been written.
      def write(data)
        # Only one synchronous call allowed at a time
        raise "already being called synchronously" unless @receiver == @controller
        
        active = @active
        @active = false
        @receiver = Actor.current
        disable if @active
        
        super(encode(data))
        
        Actor.receive do |filter|
          filter.when(Case[:tcp_write_complete, self]) do
            @receiver = @controller
            @active = active
            enable if @active
            
            return data.size
          end
          
          filter.when(Case[:tcp_closed, self]) do
            @receiver = @controller
            @active = active
            enable if @active
            
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
      
      def initialize_filter(*filterset)
        return filterset if filterset.empty?
        
        filterset.map do |filter|
          case filter
          when Array
            name = filter.shift
            case name
            when Class
              name.new(*filter)
            when Symbol
              symbol_to_filter(name).new(*filter)
            else raise ArgumentError, "unrecognized filter type: #{name.class}"
            end
          when Class
            filter.new
          when Symbol
            symbol_to_filter(filter).new
          end
        end
      end
      
      def symbol_to_filter(filter)
        case filter
        when :line then Revactor::Filters::Line
        when :packet then Revactor::Filters::Packet
        else raise ArgumentError, "unrecognized filter type: #{filter}"
        end
      end
      
      def decode(data)
        @filterset.reduce([data]) do |a, filter|
          a.reduce([]) do |a2, d|
            a2 + filter.decode(d)
          end
        end
      end
      
      def encode(message)
        result = @filterset.reverse.reduce(message) { |m, filter| filter.encode(*m) }
      end
      
      #
      # Rev::TCPSocket callbacks
      #

      def on_connect
        @receiver << T[:tcp_connected, self]
      end

      def on_connect_failed
        @receiver << T[:tcp_connect_failed, self]
      end

      def on_resolve_failed
        @receiver << T[:tcp_resolve_failed, self]
      end

      def on_close
        @receiver << T[:tcp_closed, self]
      end

      def on_read(data)
        # Run incoming message through the filter chain
        message = decode(data)
        
        if message.is_a?(Array) and not message.empty?
          message.each { |msg| @receiver << T[:tcp, self, msg] }
        elsif message
          @receiver << T[:tcp, self, message]
        else return
        end
          
        if @active == :once
          @active = false
          disable
        end
      end

      def on_write_complete
        @receiver << T[:tcp_write_complete, self]
      end
    end

    # TCP Listener returned from Revactor::TCP.listen
    class Listener < Rev::TCPListener
      attr_reader :active
      attr_reader :controller
   
      # Listen on the specified address and port.  Accepts the following options:
      #
      #   :active - Default active setting for new connections.  See the 
      #             documentation Rev::TCP::Socket#active= for more info
      #
      #   :controller - The controlling actor, default Actor.current
      #   
      def initialize(host, port, options = {})
        super(host, port)
        opts = {
          active:     false,
          controller: Actor.current
        }.merge(options)
        
        @active, @controller = opts[:active], opts[:controller]
        @filterset = options[:filter]
        
        @accepting = false
      end
      
      def active=(state)
        unless [true, false, :once].include? state
          raise ArgumentError, "must be true, false, or :once" 
        end
      
        @active = state
      end
      
      # Set the controlling actor
      def controller=(controller)
        raise ArgumentError, "controller must be an actor" unless controller.is_a? Actor
        @controller = controller
      end
      
      # Accept an incoming connection
      def accept
        raise "another actor is already accepting" if @accepting
        
        @accepting = true
        @receiver = Actor.current
        enable
        
        Actor.receive do |filter|
          filter.when(Case[:tcp_connection, self, Object]) do |message|
            @accepting = false
            return message[2]
          end
        end
      end
      
      #########
      protected
      #########
      
      #
      # Rev::TCPListener callbacks
      #
      
      def on_connection(socket)
        sock = Socket.new(socket, 
          :controller => @controller, 
          :active => @active,
          :filter => @filterset
        )
        sock.attach(evloop)
        
        @receiver << T[:tcp_connection, self, sock]
        disable
      end
    end
  end
end