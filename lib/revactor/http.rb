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
    
    # Maximum number of HTTP redirects to follow
    MAX_REDIRECTS = 10
    
    class << self
      def connect(host, port = 80, options = {})
        options[:controller] ||= Actor.current
        
        client = super
        client.attach Rev::Loop.default
      
        Actor.receive do |filter|
          filter.when(Case[Object, client]) do |message, _|
            case message
            when :http_connected
              return client
            when :http_connect_failed
              raise TCP::ConnectError, "connection refused"
            when :http_resolve_failed
              raise TCP::ResolveError, "couldn't resolve #{host}"
            else raise "unexpected message for #{client.inspect}: #{message}"
            end              
          end

          filter.after(TCP::CONNECT_TIMEOUT) do
            raise TCP::ConnectError, "connection timed out"
          end
        end
      end
      
      # Perform an HTTP request for the given method and return a response object
      def request(method, uri, options = {}, &block)
        uri = URI.parse(uri)
        
        MAX_REDIRECTS.times do
          raise URI::InvalidURIError, "invalid HTTP URI: #{uri}" unless uri.is_a? URI::HTTP
          uri.path = "/" if uri.path.empty?
        
          client = connect(uri.host, uri.port, options)
          response = client.request(method, uri.path, options, &block)
          
          return response unless response.status == 301 or response.status == 302
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
    
    def initialize(socket, options = {})        
      super(socket)
      
      @active ||= options[:active] || false
      @controller ||= options[:controller] || Actor.current
      @receiver = @controller
    end
    
    def request(method, path, options = {})
      super
      
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
      puts "on_connect_failed"
      
      super
      @receiver << T[:http_connect_failed, self]
    end
    
    def on_resolve_failed
      puts "on_resolve_failed"
      
      super
      @receiver << T[:http_resolve_failed, self]
    end
    
    def on_response_header(response_header)
      @receiver << T[:http_response_header, self, response_header]
    end
    
    def on_body_data(data)
      @receiver << T[:http, self, data]
    end
    
    def on_request_complete
      close
      @receiver << T[:http_request_complete, self]
    end
    
    def on_close
      @receiver << T[:http_closed, self]
    end
    
    def on_error(reason)
      close
      @receiver << T[:http_error, self, reason]
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
    end
    
    # The response status as an integer (e.g. 200)
    attr_reader :status
    
    # The reason returned in the http response (e.g "OK", "File not found", etc.)
    attr_reader :reason
    
    # The HTTP version returned (e.g. "HTTP/1.1")
    attr_reader :version
    
    # The content length as an integer, or nil if the length is unspecified or
    # the response is using chunked transfer encoding
    attr_reader :content_length
    
    # Access to the raw header fields from the request
    attr_reader :header_fields
    
    # Is the request encoding chunked?
    def chunked_encoding?; @chunked_encoding; end
  end
end