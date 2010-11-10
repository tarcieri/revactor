#--
# Copyright (C)2007-10 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Revactor
  module Filter
    # A filter for "packet" protocols which are framed using a fix-sized
    # length prefix followed by a message body, such as DRb.  Either 16-bit
    # or 32-bit prefixes are supported.
    class Packet
      def initialize(size = 4)
        unless size == 2 or size == 4
          raise ArgumentError, 'only 2 or 4 byte prefixes are supported' 
        end
        
        @prefix_size = size
        @data_size = 0
        
        @mode = :prefix
        @buffer = IO::Buffer.new
      end

      # Callback for processing incoming frames
      def decode(data)
        received = []
        @buffer << data
      
        begin  
          if @mode == :prefix
            break if @buffer.size < @prefix_size
            prefix = @buffer.read @prefix_size
            @data_size = prefix.unpack(@prefix_size == 2 ? 'n' : 'N').first
            @mode = :data
          end
        
          break if @buffer.size < @data_size
          received << @buffer.read(@data_size)
          @mode = :prefix
        end until @buffer.empty?
        
        received
      end

      # Send a packet with a specified size prefix
      def encode(*data)
        data.inject('') do |s, d|
          raise ArgumentError, 'packet too long for prefix length' if d.size >= 256 ** @prefix_size
          s << [d.size].pack(@prefix_size == 2 ? 'n' : 'N') << d
        end
      end
    end
  end
end