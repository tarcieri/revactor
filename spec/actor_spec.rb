#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/actor'

describe Actor do
  describe "creation" do
    it "creates a base Actor with Actor.start" do
      Actor.start do
        Fiber.current.should be_an_instance_of(Actor)
      end
    end
  
    it "allows creation of new Actors with Actor.new" do
      Actor.new do
        Fiber.current.should be_an_instance_of(Actor)
      end
    end
    
    it "allows creation of new Actors with Actor.spawn" do
      Actor.spawn do
        Fiber.current.should be_an_instance_of(Actor)
      end
    end
    
    it "allows arguments to be passed when an Actor is created" do
      [:new, :spawn].each do |meth|
        Actor.send(meth, 1, 2, 3) do |foo, bar, baz|
          [foo, bar, baz].should == [1, 2, 3]
        end
      end
    end
  end
  
  describe "current" do
    it "allows the current Actor to be retrieved" do
      Actor.new do
        Actor.current.should be_an_instance_of(Actor)
      end
    end
  
    it "disallows retrieving the current Actor unless the Actor environment is started" do
      proc { Actor.current }.should raise_error(ActorError)
    end
  end
  
  describe "receive" do
    it "returns the value of the matching filter action" do
      actor_run = false
      actor = Actor.new do
        Actor.receive do |filter|
          filter.when(:foo) { |message| :bar }
        end.should == :bar
        
        # Make sure the spec actually ran the actor
        actor_run = true
      end
      
      actor << :foo
      actor_run.should be_true
    end
    
    it "filters messages with ===" do
      actor_run = false
      actor = Actor.new do
        results = []
        3.times do
          results << Actor.receive do |filter|
            filter.when(/third/) { |m| m }
            filter.when(/first/) { |m| m }
            filter.when(/second/) { |m| m }
          end
        end
        results.should == ['first message', 'second message', 'third message']
        actor_run = true
      end
      
      ['first message', 'second message', 'third message'].each { |m| actor << m }
      actor_run.should be_true
    end
    
    it "filters messages by Proc" do
      actor_run = false
      actor = Actor.new do
        results = []
        3.times do
          results << Actor.receive do |filter|
            filter.when(proc { |m| m[1] == :second }) { |m| m[0] }
            filter.when(proc { |m| m[1] == :first })  { |m| m[0] }
            filter.when(proc { |m| m[1] == :third })  { |m| m[0] }
          end
        end
        results.should == ['first message', 'second message', 'third message']
        actor_run = true
      end
      
      [
        ['first message',  :first], 
        ['second message', :second], 
        ['third message',  :third]
      ].each { |m| actor << m }
      actor_run.should be_true
    end
    
    it "times out if a message isn't received after the specifed interval" do
      actor_run = false
      actor = Actor.new do
        Actor.receive do |filter|
          filter.when(:foo) { :wrong }
          filter.after(0.01) { :right }
        end.should == :right
        actor_run = true
      end
      actor_run.should be_true
    end
    
    it "matches any message with Actor::ANY_MESSAGE" do
      actor_run = false
      actor = Actor.new do
        result = []
        3.times do
          result << Actor.receive do |filter|
            filter.when(Actor::ANY_MESSAGE) { |m| m }
          end
        end
        
        result.should == [:foo, :bar, :baz]
        actor_run = true
      end
      
      [:foo, :bar, :baz].each { |m| actor << m }
      actor_run.should be_true
    end
  end
  
  it "detects dead actors" do
    actor = Actor.new do
      Actor.receive do |filter|
        filter.when(Actor::ANY_MESSAGE) {}
      end
    end
    
    actor.dead?.should be_false
    actor << :foobar
    actor.dead?.should be_true
  end
end