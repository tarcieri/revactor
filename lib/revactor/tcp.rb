#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

module Revactor
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
        filter.when(proc { |m| m[1] == socket }) do |message|
          case message.first
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
            self
          }
        end
      end
      
      def initialize(socket, options = {})        
        super(socket)
        
        @active ||= options[:active] || false
        @controller ||= options[:controller] || Actor.current
        @filter = initialize_filter(options[:filter])
        @read_buffer = ''
      end
      
      # Enable or disable active mode data reception.  State can be any
      # of the following:
      #
      #   true - All received data is sent to the controlling actor
      #   false - Receiving data is disabled
      #   :once - A single message will be sent to the controlling actor
      #           then active mode will be disabled
      def active=(state)
        unless [true, false, :once].include? state
          raise ArgumentError, "must be true, false, or :once" 
        end
        
        if [true, :once].include?(state)
          unless @read_buffer.empty?
            @controller << [:tcp, self, @read_buffer]
            @read_buffer = ''
            return if state == :once
          end
          
          enable unless enabled?
        end
        
        @active = state
      end
      
      # Set the controlling actor
      def controller=(controller)
        raise ArgumentError, "controller must be an actor" unless controller.is_a? Actor
        @controller = controller
      end
      
      # Read data from the socket synchronously.  If a length is specified
      # then the call blocks until the given length has been read.  Otherwise
      # the call blocks until it has read any data.
      def read(length = nil)
        unless @read_buffer.empty?
          if length.nil?
            data = @read_buffer
            @read_buffer = ''
            return data
          end
          
          # Slow in Ruby 1.9 :(
          # return @read_buffer.slice!(0, length) if @read_buffer.size >= length
          if @read_buffer.size >= length
            data = @read_buffer[0..(length - 1)]
            @read_buffer = @read_buffer[length..@read_buffer.size]
            return data
          end
        end
              
        was_enabled = enabled?
        enable unless enabled?
        
        loop do
          Actor.receive do |filter|
            filter.when(proc do |m| 
              [:tcp, :tcp_closed].include?(m[0]) and m[1] == self 
            end) do |message|
              case message.first
              when :tcp
                if length.nil?
                  disable unless was_enabled
                  return message[2]
                end
                
                @read_buffer << message[2]
                
                if @read_buffer.size >= length
                  disable unless was_enabled
                  
                  # Slow in Ruby 1.9 :(
                  # return @read_buffer.slice!(0, length) 
                  data = @read_buffer[0..(length - 1)]
                  @read_buffer = @read_buffer[length..@read_buffer.size]
                  return data
                end
              when :tcp_closed
                raise EOFError, "connection closed"
              end
            end
          end
        end
      end
      
      # Write data to the socket.  The call blocks until all data has been written.
      def write(data)
        super
        
        Actor.receive do |filter|
          filter.when(proc do |m| 
            [:tcp_write_complete, :tcp_closed].include?(m[0]) and m[1] == self 
          end) do |message|
            case message.first
            when :tcp_write_complete
              return data.size
            when :tcp_closed
              raise EOFError, "connection closed"
            end
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
      
      def initialize_filter(filter)
        return [] unless filter
        
        filter.map do |f|
          case filter
          when Array
            name = f.shift
            case name
            when Class
              name.new(*f)
            when Symbol
              symbol_to_filter(name).new(*f)
            else raise ArgumentError, "unrecognized filter type: #{name.class}"
            end
          when Class
            f.new
          when Symbol
            symbol_to_filter(f).new
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
      
      def decode(message)
        return message if @filter.empty?
        
        @filter.each do |f|
          case message
          when Array
            message = message.reduce([]) { |a, m| a + f.decode(message) }
          else
            message = f.decode(message)
          end
          
          return [] if message.nil? or message.empty?
        end
        
        message
      end
      
      #
      # Rev::TCPSocket callbacks
      #

      def on_connect
        @controller << [:tcp_connected, self]
      end

      def on_connect_failed
        @controller << [:tcp_connect_failed, self]
      end

      def on_resolve_failed
        @controller << [:tcp_resolve_failed, self]
      end

      def on_close
        @controller << [:tcp_closed, self]
      end

      def on_read(data)
        # Run incoming message through the filter chain
        message = decode(data)
        
        if message.is_a?(Array) and not message.empty?
          message.each { |msg| @controller << [:tcp, self, msg] }
        elsif message
          @controller << [:tcp, self, message]
        else return
        end
          
        if @active == :once
          @active = false
          disable
        end
      end

      def on_write_complete
        @controller << [:tcp_write_complete, self]
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
        enable
        
        Actor.receive do |filter|
          filter.when(proc { |m| m[0] == :tcp_connection and m[1] == self }) do |message|
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
        sock = Socket.new(socket, :controller => @controller, :active => @active)
        sock.attach(Rev::Loop.default)
        
        @controller << [:tcp_connection, self, sock]
        disable
      end
    end
  end
end