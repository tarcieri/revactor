#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/tcp'

TEST_HOST = '127.0.0.1'

# Chosen with dice, guaranteed to be random!
RANDOM_PORT = 10103

describe Revactor::TCP do
  before :each do
    @actor_run = false
    @server = TCPServer.new(TEST_HOST, RANDOM_PORT)
  end
  
  after :each do
    @server.close unless @server.closed?
  end
  
  it "connects to remote servers" do
    Actor.start do
      sock = Revactor::TCP.connect(TEST_HOST, RANDOM_PORT)
      sock.should be_an_instance_of(Revactor::TCP::Socket)
      @server.accept.should be_an_instance_of(TCPSocket)
      
      sock.close
      @actor_run = true
    end
    
    @actor_run.should be_true
  end
  
  it "listens for remote connections" do
    @server.close # Don't use it for this one...
    
    Actor.start do
      server = Revactor::TCP.listen(TEST_HOST, RANDOM_PORT)
      server.should be_an_instance_of(Revactor::TCP::Listener)
      
      s1 = TCPSocket.open(TEST_HOST, RANDOM_PORT)
      s2 = server.accept
      
      server.close
      s2.close
      @actor_run = true
    end
    
    @actor_run.should be_true
  end
  
  it "reads data" do
    Actor.start do
      s1 = Revactor::TCP.connect(TEST_HOST, RANDOM_PORT)
      s2 = @server.accept
    
      s2.write 'foobar'
      s1.read(6).should == 'foobar'
    
      s1.close
      @actor_run = true
    end
  
    @actor_run.should be_true
  end

  it "writes data" do
    Actor.start do
      s1 = Revactor::TCP.connect(TEST_HOST, RANDOM_PORT)
      s2 = @server.accept
      
      s1.write 'foobar'
      s2.read(6).should == 'foobar'
      
      s1.close
      @actor_run = true
    end
    
    @actor_run.should be_true  
  end
end