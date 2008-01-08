#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/filters/packet.rb'

describe Revactor::Filters::Packet do
  describe 'Prefix' do
    it "supports 2 or 4-byte prefixes" do
      proc { [2,4].each { |n| Revactor::Filters::Packet::Prefix.new(n) } }.should_not raise_error
    end
  
    it "raises an exception if instantiated with an invalid prefix size" do
      proc { Revactor::Filters::Packet::Prefix.new(3) }.should raise_error
    end
  
    it "uses a 2-byte prefix as the default" do
      Revactor::Filters::Packet::Prefix.new.size.should == 2
    end
  
    it "decodes 2-byte prefixes from network byte order" do
      @prefix = Revactor::Filters::Packet::Prefix.new(2)
      @prefix.append [42].pack('n')
      @prefix.payload_length.should == 42
    end
  
    it "decodes 4-byte prefixes from network byte order" do
      @prefix = Revactor::Filters::Packet::Prefix.new(4)
      @prefix.append [42].pack('N')
      @prefix.payload_length.should == 42
    end
  
    it "allows the prefix to be written incrementally" do
      @prefix = Revactor::Filters::Packet::Prefix.new(2)
      value = [42].pack('n')
    
      @prefix.append value[0..0]
      @prefix.read?.should be_false
      proc { @prefix.payload_length }.should raise_error
    
      @prefix.append value[1..1]
      @prefix.read?.should be_true
      @prefix.payload_length.should == 42
    end
  
    it "returns data which exceeds the prefix length" do
      @prefix = Revactor::Filters::Packet::Prefix.new(2)
      @prefix.append([42].pack('n') << "extra").should == 'extra'
    end
  
    it "resets to a consistent state after being used" do
      @prefix = Revactor::Filters::Packet::Prefix.new(2)
      @prefix.append [17].pack('n')
    
      @prefix.reset!
      @prefix.read?.should be_false
      proc { @prefix.payload_length }.should raise_error
    
      @prefix.append [21].pack('n')
      @prefix.payload_length.should == 21
    end
  end

  before(:each) do
    @payload = "A test string"
  end
  
  it "decodes frames with 2-byte prefixes" do
    filter = Revactor::Filters::Packet.new(2)
    filter.decode([@payload.length].pack('n') << @payload).should == [@payload]
  end
  
  it "encodes frames with 2-byte prefixes" do
    filter = Revactor::Filters::Packet.new(2)
    filter.encode(@payload).should == [@payload.length].pack('n') << @payload
  end
    
  it "decodes frames with 4-byte prefixes" do
    @filter = Revactor::Filters::Packet.new(4)    
    @filter.decode([@payload.length].pack('N') << @payload).should == [@payload]
  end
  
  it "encodes frames with 4-byte prefixes" do
    @filter = Revactor::Filters::Packet.new(4)    
    @filter.encode(@payload).should == [@payload.length].pack('N') << @payload
  end
  
  it "reassembles fragmented frames" do
    filter = Revactor::Filters::Packet.new(2)
    
    msg1 = 'foobar'
    msg2 = 'baz'
    msg3 = 'quux'
    
    packet1 = [msg1.length].pack('n') << msg1
    packet2 = [msg2.length].pack('n') << msg2
    packet3 = [msg3.length].pack('n') << msg3
        
    chunks = []
    chunks[0] = packet1.slice(0, 1)
    chunks[1] = packet1.slice(1, packet1.size) << packet2.slice(0, 1)
    chunks[2] = packet2.slice(1, packet2.size - 1)
    chunks[3] = packet2.slice(packet2.size, 1) << packet3
    
    chunks.reduce([]) { |a, chunk| a + filter.decode(chunk) }.should == [msg1, msg2, msg3]
  end

  it "raises an exception for overlength frames" do
    filter = Revactor::Filters::Packet.new(2)
    payload = 'X' * 65537
    proc { filter.encode payload }.should raise_error(ArgumentError)
  end
end