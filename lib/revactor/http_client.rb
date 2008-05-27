#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

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
    
    # Statuses which indicate the request was redirected
    REDIRECT_STATUSES = [301, 302, 303, 307]
    
    class << self
      def connect(host, port = 80)        
        client = super
        client.instance_variable_set :@receiver, Actor.current
        client.attach Rev::Loop.default
      
        Actor.receive do |filter|
          filter.when(T[Object, client]) do |message, _|
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
            client.close unless client.closed?
            raise TCP::ConnectError, "connection timed out"
          end
        end
      end
      
      # Perform an HTTP request for the given method and return a response object
      def request(method, uri, options = {})
        follow_redirects = options.has_key?(:follow_redirects) ? options[:follow_redirects] : true
        uri = URI.parse(uri)
        
        MAX_REDIRECTS.times do
          raise URI::InvalidURIError, "invalid HTTP URI: #{uri}" unless uri.is_a? URI::HTTP
          request_options = uri.is_a?(URI::HTTPS) ? options.merge(:ssl => true) : options
        
          client = connect(uri.host, uri.port)
          response = client.request(method, uri.request_uri, request_options)
          
          # Request complete
          unless follow_redirects and REDIRECT_STATUSES.include? response.status
            return response unless block_given?
            
            begin
              yield response
            ensure
              response.close
            end
            
            return
          end
          
          response.close
          
          location = response.headers['location']
          raise "redirect with no location header: #{uri}" if location.nil?
          
          # Convert path-based redirects to URIs
          unless /^[a-z]+:\/\// === location
            location = "#{uri.scheme}://#{uri.host}" << File.expand_path(location, uri.path)
          end
          
          uri = URI.parse(location)
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
      if options[:ssl]
        ssl_handshake
        
        Actor.receive do |filter|
          filter.when(T[:https_connected, self]) do
            disable
          end
          
          filter.when(T[:http_closed, self]) do
            raise EOFError, "SSL handshake failed"
          end
          
          filter.after(TCP::CONNECT_TIMEOUT) do
            close unless closed?
            raise TCP::ConnectError, "SSL handshake timed out"
          end
        end
      end
      
      super
      enable
      
      Actor.receive do |filter|
        filter.when(T[:http_response_header, self]) do |_, _, response_header|
          return HttpResponse.new(self, response_header)
        end
        
        filter.when(T[:http_error, self, Object]) do |_, _, reason|
          close unless closed?
          raise HttpClientError, reason
        end
        
        filter.when(T[:http_closed, self]) do
          raise EOFError, "connection closed unexpectedly"
        end

        filter.after(REQUEST_TIMEOUT) do
          @finished = true
          close unless closed?
          
          raise HttpClientError, "request timed out"
        end
      end
    end
    
    #########
    protected
    #########
    
    def ssl_handshake
      require 'rev/ssl'
      extend Rev::SSL
      ssl_client_start
    end
    
    def on_connect
      super
      @receiver << T[:http_connected, self]
    end
    
    def on_ssl_connect
      @receiver << [:https_connected, self]
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
      @finished = true
      @receiver << T[:http_request_complete, self]
      close
    end
    
    def on_close
      @receiver << T[:http_closed, self] unless @finished
    end
    
    def on_error(reason)
      @finished = true
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
      
      # Convert header fields hash from LIKE_THIS to like-this
      @headers = response_header.inject({}) do |h, (k, v)| 
        h[k.split('_').map(&:downcase).join('-')] = v; h
      end
      
      # Extract Transfer-Encoding if available
      @transfer_encoding = @headers.delete('transfer-encoding')
      
      # Extract Content-Type if available
      @content_type = @headers.delete('content-type')
      
      # Extract Content-Encoding if available
      @content_encoding = @headers.delete('content-encoding') || 'identity'
    end
    
    # The response status as an integer (e.g. 200)
    attr_reader :status
    
    # The reason returned in the http response (e.g "OK", "File not found", etc.)
    attr_reader :reason
    
    # The HTTP version returned (e.g. "HTTP/1.1")
    attr_reader :version
    
    # The encoding of the transfer
    attr_reader :transfer_encoding
    
    # The encoding of the content.  Gzip encoding will be processed automatically
    attr_reader :content_encoding
    
    # The MIME type of the response's content
    attr_reader :content_type
    
    # The content length as an integer, or nil if the length is unspecified or
    # the response is using chunked transfer encoding
    attr_reader :content_length
    
    # Access to the raw header fields from the request
    attr_reader :headers
    
    # Is the request encoding chunked?
    def chunked_encoding?; @chunked_encoding; end
    
    # Incrementally read the response body
    def read_body
      @client.controller = Actor.current
      @client.enable if @client.attached? and not @client.enabled?
      
      Actor.receive do |filter|
        filter.when(T[:http, @client]) do |_, _, data|
          return data
        end
        
        filter.when(T[:http_request_complete, @client]) do
          return nil
        end
        
        filter.when(T[:http_error, @client]) do |_, _, reason|
          raise HttpClientError, reason
        end
        
        filter.when(T[:http_closed, @client]) do
          raise EOFError, "connection closed unexpectedly"
        end

        filter.after(HttpClient::READ_TIMEOUT) do
          @finished = true
          @client.close unless @client.closed?          
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
      
      if content_length and body.size != content_length
        raise HttpClientError, "body size does not match Content-Length (#{body.size} of #{content_length})"
      end
      
      @body
    end
    
    # Explicitly close the connection
    def close
      return if @client.closed?
      @finished = true
      @client.controller = Actor.current
      @client.close      
    end
  end
end
