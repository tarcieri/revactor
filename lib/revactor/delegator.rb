#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

# A Delegator whose delegate runs in a separate Actor.  This allows
# an easy method for constructing synchronous calls to a separate Actor
# which cause the current Actor to block until they complete.
class Revactor::Delegator  
  # Create a new delegator for the given object
  def initialize(obj)
    @obj = obj
    @running = true
    @actor = Actor.spawn(&method(:start))
  end
  
  # Stop the delegator Actor
  def stop
    @actor << :stop
    nil
  end
  
  # Send a message to the Actor delegate
  def send(meth, *args, &block)
    @actor << T[:call, Actor.current, meth, args, block]
    Actor.receive do |filter|
      filter.when(Case[:call_reply, @actor, Object]) { |_, _, reply| reply }
      filter.when(Case[:call_error, @actor, Object]) { |_, _, ex| raise ex }
    end
  end
  
  alias_method :method_missing, :send
  
  #########
  protected
  #########
  
  # Start the server
  def start
    loop do
      Actor.receive do |filter|
        filter.when(:stop)  { |_| return }
        filter.when(Object) { |message| handle_message(message) }
      end
    end
  end
  
  # Dispatch the incoming message to the appropriate handler
  def handle_message(message)
    case message.first
    when :call then handle_call(message)
    else @obj.__send__(:on_message, message) if @obj.respond_to? :on_message
    end
  end
  
  # Wrapper for calling the provided object's handle_call method
  def handle_call(message)
    _, from, meth, args, block = message
    
    begin
      result = @obj.__send__(meth, *args, &block)
      from << T[:call_reply, Actor.current, result]
    rescue => ex
      from << T[:call_error, Actor.current, ex]
    end
  end
end