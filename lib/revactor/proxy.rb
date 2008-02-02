#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

# A simple method proxy which converts all method calls to the Actor into messages
# with method_missing.  The given object must respond_to? :run, which will be called
# within the scope of the new Actor.
class Revactor::Proxy < Actor
  class << self
    def spawn(obj)
      raise ArgumentError, "provided object must respond to :run" unless obj.respond_to? :run
      super { obj.run }
    end
    
    def spawn_link(obj)
      raise ArgumentError, "provided object must respond to :run" unless obj.respond_to? :run
      super { obj.run }
    end
  
    def new(obj)
      return super(obj) if obj.is_a? Fiber
      spawn(obj)
    end
  end
  
  def method_missing(meth, *args)
    self << T[meth, *args]
  end
end