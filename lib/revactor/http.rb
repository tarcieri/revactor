#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'
require 'uri'

module Revactor
  # Thrown for all HTTP-specific errors
  class HttpClientError < StandardError; end
  
  # A high performance HTTP client which wraps the asynchronous client in Rev
  class HttpClient < Rev::HttpClient
    # Default timeout for HTTP requests (until the response header is received)
    REQUEST_TIMEOUT = 60
    
    # Read timeout for responses from the server
    READ_TIMEOUT = 30
    
    # Maximum number of HTTP redirects to follow
    MAX_REDIRECTS = 10
    
    class << self
      def connect(host, port = 80)        
        client = super
        client.instance_eval { @receiver = Actor.current }
        client.attach Rev::Loop.default
      
        Actor.receive do |filter|
          filter.when(Case[Object, client]) do |message, _|
            case message
            when :http_connected
              client.disable
              return client
            when :http_connect_failed
              raise TCP::ConnectError, "connection refused"
            when :http_resolve_failed
              raise TCP::ResolveError, "couldn't resolve #{host}"
            else raise "unexpected message for #{client.inspect}: #{message.inspect}"
            end              
          end

          filter.after(TCP::CONNECT_TIMEOUT) do
            raise TCP::ConnectError, "connection timed out"
          end
        end
      end
      
      # Perform an HTTP request for the given method and return a response object
      def request(method, uri, options = {}, &block)
        follow_redirects = options.has_key?(:follow_redirects) ? options[:follow_redirects] : true
        uri = URI.parse(uri)
        
        MAX_REDIRECTS.times do
          raise URI::InvalidURIError, "invalid HTTP URI: #{uri}" unless uri.is_a? URI::HTTP
          uri.path = "/" if uri.path.empty?
          request_options = uri.is_a?(URI::HTTPS) ? options.merge(:ssl => true) : options
        
          client = connect(uri.host, uri.port)
          response = client.request(method, uri.path, request_options, &block)
          
          return response unless follow_redirects and [301, 302].include? response.status
          response.close
          
          uri = URI.parse(response.header_fields['Location'])
        end
        
        raise HttpClientError, "exceeded maximum of #{MAX_REDIRECTS} redirects"
      end
      
      Rev::HttpClient::ALLOWED_METHODS.each do |meth|
        module_eval <<-EOD
          def #{meth}(uri, options = {}, &block)
            request(:#{meth}, uri, options, &block)
          end
        EOD
      end
    end
    
    def initialize(socket)
      super
      @controller = @receiver ||= Actor.current
    end
    
    # Change the controlling Actor for active mode reception
    # Set the controlling actor
    def controller=(controller)
      raise ArgumentError, "controller must be an actor" unless controller.is_a? Actor
      
      @receiver = controller if @receiver == @controller
      @controller = controller
    end
    
    # Initiate an HTTP request for the given path using the given method
    # Supports the following options:
    #
    #   ssl: Boolean
    #     If true, an HTTPS request will be made
    #
    #   head: {Key: Value, Key2: Value2}
    #     Specify HTTP headers, e.g. {'Connection': 'close'}
    #
    #   query: {Key: Value}
    #     Specify query string parameters (auto-escaped)
    #
    #   cookies: {Key: Value}
    #     Specify hash of cookies (auto-escaped)
    #
    #   body: String
    #     Specify the request body (you must encode it for now)
    #
    def request(method, path, options = {})
      if options.delete(:ssl)
        require 'rev/ssl'
        extend Rev::SSL
        ssl_start
      end
      
      super
      enable
      
      Actor.receive do |filter|
        filter.when(Case[:http_response_header, self, Object]) do |_, _, response_header|
          return HttpResponse.new(self, response_header)
        end
        
        filter.when(Case[:http_closed, self]) do
          raise EOFError, "connection closed unexpectedly"
        end
        
        filter.when(Case[:http_error, self, Object]) do |_, _, reason|
          raise HttpClientError, reason
        end

        filter.after(REQUEST_TIMEOUT) do
          close
          raise HttpClientError, "request timed out"
        end
      end
    end
    
    #########
    protected
    #########
    
    def on_connect
      super
      @receiver << T[:http_connected, self]
    end
    
    def on_connect_failed
      super
      @receiver << T[:http_connect_failed, self]
    end
    
    def on_resolve_failed
      super
      @receiver << T[:http_resolve_failed, self]
    end
    
    def on_response_header(response_header)
      disable
      @receiver << T[:http_response_header, self, response_header]
    end
    
    def on_body_data(data)
      disable if enabled? and not @active 
      @receiver << T[:http, self, data]
    end
    
    def on_request_complete
      @receiver << T[:http_request_complete, self]
      close
    end
    
    def on_close
      @receiver << T[:http_closed, self]
    end
    
    def on_error(reason)
      @receiver << T[:http_error, self, reason]
      close
    end
  end
  
  # An object representing a response to an HTTP request
  class HttpResponse
    def initialize(client, response_header)
      @client = client
      
      # Copy these out of the original Rev response object, then discard it
      @status = response_header.status
      @reason = response_header.http_reason
      @version = response_header.http_version
      @content_length = response_header.content_length
      @chunked_encoding = response_header.chunked_encoding?
      
      # Convert header fields hash from LIKE_THIS to Like-This
      @header_fields = response_header.reduce({}) { |h, (k, v)| h[k.split('_').map(&:capitalize).join('-')] = v; h }
      
      # Extract Content-Type if available
      @content_type = @header_fields.delete('Content-Type')
    end
    
    # The response status as an integer (e.g. 200)
    attr_reader :status
    
    # The reason returned in the http response (e.g "OK", "File not found", etc.)
    attr_reader :reason
    
    # The HTTP version returned (e.g. "HTTP/1.1")
    attr_reader :version
    
    # The MIME type of the response's content
    attr_reader :content_type
    
    # The content length as an integer, or nil if the length is unspecified or
    # the response is using chunked transfer encoding
    attr_reader :content_length
    
    # Access to the raw header fields from the request
    attr_reader :header_fields
    
    # Is the request encoding chunked?
    def chunked_encoding?; @chunked_encoding; end
    
    # Incrementally read the response body
    def read_body
      @client.controller = Actor.current
      @client.enable if @client.attached? and not @client.enabled?
      
      Actor.receive do |filter|
        filter.when(Case[:http, @client, Object]) do |_, _, data|
          return data
        end
        
        filter.when(Case[:http_request_complete, @client]) do
          # Consume the :http_closed message
          Actor.receive do |filter| 
            filter.when(Case[:http_closed, @client]) {}
          end
          
          return nil
        end
        
        filter.when(Case[:http_closed, @client]) do
          raise EOFError, "connection closed unexpectedly"
        end
        
        filter.when(Case[:http_error, @client, Object]) do |_, _, reason|
          raise HttpClientError, reason
        end

        filter.after(HttpClient::READ_TIMEOUT) do
          @client.close
          raise HttpClientError, "read timed out"
        end
      end
    end
    
    # Consume the entire response body and return it as a string.
    # The body is stored for subsequent access.
    # A maximum body length may optionally be specified
    def body(maxlength = nil)
      return @body if @body
      @body = ""
      
      begin
        while (data = read_body)
          @body << data
          
          if maxlength and @body.size > maxlength
            raise HttpClientError, "overlength body"
          end
        end
      rescue EOFError => ex
        # If we didn't get a Content-Length and encoding isn't chunked
        # we have to depend on the socket closing to detect end-of-body
        # Otherwise the EOFError was unexpected and should be raised
        unless (content_length.nil? or content_length.zero?) and not chunked_encoding?
          raise ex 
        end
      end
      
      @body
    end
    
    # Explicitly close the connection
    def close
      return if @client.closed?
      @client.controller = Actor.current
      @client.close
      
      # Wait for the :http_closed message
      Actor.receive { |f| f.when(Case[:http_closed, @client]) {} }
    end
  end
end