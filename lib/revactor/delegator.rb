#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

# A Delegator whose delegate runs in a separate Actor.  This allows
# an easy method for constructing synchronous calls to a separate Actor
# which cause the current Actor to block until they complete.
class Revactor::Delegator
  # How long to wait for a response to a call before timing out
  # This value also borrowed from Erlang.  More cargo culting!
  DEFAULT_CALL_TIMEOUT = 5
  
  # Create a new server.  Accepts the following options:
  #
  #   register: Register the Actor in the Actor registry under
  #             the given term
  #
  # Any options passed after the options hash are passed to the
  # start method of the given object.
  #
  def initialize(obj, options = {}, *args)
    @obj = obj
    @timeout = nil
    @state = obj.start(*args)
    @actor = Actor.new(&method(:start).to_proc)
    
    Actor[options[:register]] = @actor if options[:register]
  end
  
  # Call the server with the given message
  def call(message, options = {})
    options[:timeout] ||= DEFAULT_CALL_TIMEOUT
    
    @actor << T[:call, Actor.current, message]
    Actor.receive do |filter|
      filter.when(Case[:call_reply, @actor, Object]) { |_, _, reply| reply }
      filter.when(Case[:call_error, @actor, Object]) { |_, _, ex| raise ex }
      filter.after(options[:timeout]) { raise 'timeout' }
    end
  end
  
  # Send a cast to the server
  def cast(message)
    @actor << T[:cast, message]
    message
  end
  
  #########
  protected
  #########
  
  # Start the server
  def start
    @running = true
    while @running do
      Actor.receive do |filter|
        filter.when(Object) { |message| handle_message(message) }
        filter.after(@timeout) { stop(:timeout) } if @timeout
      end
    end
  end
  
  # Dispatch the incoming message to the appropriate handler
  def handle_message(message)
    case message.first
    when :call then handle_call(message)
    when :cast then handle_cast(message)
    else handle_info(message)
    end
  end
  
  # Wrapper for calling the provided object's handle_call method
  def handle_call(message)
    _, from, body = message
    
    begin
      result = @obj.handle_call(body, from, @state)
      case result.first
      when :reply
        _, reply, @state, @timeout = result
        from << T[:call_reply, Actor.current, reply]
      when :noreply
        _, @state, @timeout = result
      when :stop
        _, reason, @state = result
        stop(reason)
      end
    rescue Exception => ex
      log_exception(ex)
      from << T[:call_error, Actor.current, ex]
    end
  end
  
  # Wrapper for calling the provided object's handle_cast method
  def handle_cast(message)
    _, body = message
  
    begin
      result = @obj.handle_cast(body, @state)
      case result.first
      when :noreply
        _, @state, @timeout = result
      when :stop
        _, reason, @state = result
        stop(reason)
      end
    rescue Exception => e
      log_exception(e)
    end
  end
  
  # Wrapper for calling the provided object's handle_info method
  def handle_info(message)
    begin
      result = @obj.handle_info(message, @state)
      case result.first
      when :noreply
        _, @state, @timeout = result
      when :stop
        _, reason, @state = result
        stop(reason)
      end
    rescue Exception => e
      log_exception(e)
    end
  end
  
  # Stop the server
  def stop(reason)
    @running = false
    @obj.terminate(reason, @state)
  end
  
  # Log an exception
  def log_exception(exception)
    # FIXME this should really go to a logger, not STDERR
    STDERR.puts "Rev::Server exception: #{exception}"
    STDERR.puts exception.backtrace
  end
end