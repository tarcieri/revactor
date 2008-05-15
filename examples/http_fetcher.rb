require 'zlib'
require 'stringio'

require 'rubygems'
require 'revactor'

# A concurrent HTTP fetcher, implemented using a central dispatcher which
# scatters requests to a worker pool.
#
# The HttpFetcher class is callback-driven and intended for subclassing.
# When a request completes successfully, the on_success callback is called.
# An on_failure callback represents non-200 HTTP responses, and on_error
# delivers any exceptions which occured during the fetch.
class HttpFetcher
  def initialize(nworkers = 8)
    @_nworkers = nworkers
    @_workers, @_queue = [], []
    nworkers.times { @_workers << Worker.spawn(Actor.current) }
  end
  
  def get(url, *args)
    if @_workers.empty?
      @_queue << T[url, args]
    else
      @_workers.shift << T[:fetch, url, args]
    end
  end

  def run
    while true
      Actor.receive do |filter|
        filter.when(T[:ready]) do |_, worker|
          if @_queue.empty?
            @_workers << worker
            on_empty if @_workers.size == @_nworkers
          else
            worker << T[:fetch, *@_queue.shift]
          end
        end

        filter.when(T[:fetched]) { |_, url, document, args| on_success url, document, *args }
        filter.when(T[:failed])  { |_, url, status, args| on_failure url, status, *args }
        filter.when(T[:error])   { |_, url, ex, args| on_error url, ex, *args }
      end
    end
  end
  
  def on_success(url, document, *args); end
  def on_failure(url, status, *args); end
  def on_error(url, ex, *args); end
  def on_empty; exit; end
  
  class Worker
    extend Actorize
    
    def initialize(fetcher)
      @fetcher = fetcher      
      loop { wait_for_request }
    end
      
    def wait_for_request
      Actor.receive do |filter|
        filter.when(T[:fetch]) do |_, url, args|
          begin
            fetch url, args
          rescue => ex
            @fetcher << T[:error, url, ex, args]
          end
          
          # FIXME this should be unnecessary, but the HTTP client "leaks" messages
          Actor.current.mailbox.clear
          @fetcher << T[:ready, Actor.current]
        end
      end
    end
    
    def fetch(url, args)
      Actor::HttpClient.get(url, :head => {'Accept-Encoding' => 'gzip'}) do |response|
        if response.status == 200        
          @fetcher << T[:fetched, url, decode_body(response), args]
        else
          @fetcher << T[:failed, url, response.status, args]
        end
      end
    end
    
    def decode_body(response)
      if response.content_encoding == 'gzip'
        Zlib::GzipReader.new(StringIO.new(response.body)).read
      else
        response.body
      end
    end
  end
end