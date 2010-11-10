#--
# Copyright (C)2009-10 Eric Wong, Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.expand_path('../spec_helper', __FILE__)
require 'tempfile'

describe Revactor::UNIX do
  before :each do
    @actor_run = false
    @tmp = Tempfile.new('unix.sock')
    File.unlink(@tmp.path)
    @server = UNIXServer.new(@tmp.path)
  end

  after :each do
    @server.close unless @server.closed?
    File.unlink(@tmp.path)
  end

  it "connects to remote servers" do
    sock = Revactor::UNIX.connect(@tmp.path)
    sock.should be_an_instance_of(Revactor::UNIX::Socket)
    @server.accept.should be_an_instance_of(UNIXSocket)

    sock.close
  end

  it "listens for remote connections" do
    # Don't use their server for this one...
    @server.close
    File.unlink(@tmp.path)

    server = Revactor::UNIX.listen(@tmp.path)
    server.should be_an_instance_of(Revactor::UNIX::Listener)

    s1 = UNIXSocket.open(@tmp.path)
    s2 = server.accept

    server.close
    s2.close
  end

  it "reads data" do
    s1 = Revactor::UNIX.connect(@tmp.path)
    s2 = @server.accept

    s2.write 'foobar'
    s1.read(6).should == 'foobar'

    s1.close
  end

  it "writes data" do
    s1 = Revactor::UNIX.connect(@tmp.path)
    s2 = @server.accept

    s1.write 'foobar'
    s2.read(6).should == 'foobar'

    s1.close
  end
end
