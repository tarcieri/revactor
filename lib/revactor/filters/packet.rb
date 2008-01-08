#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Revactor
  module Filters
    class Packet
      # Class for processing size prefixes in packet frames
      class Prefix
        attr_reader :size, :data

        def initialize(size = 2)
          unless size == 2 or size == 4
            raise ArgumentError, 'only 2 or 4 byte prefixes are supported' 
          end

          @size = size
          reset!
        end

        # Has the entire prefix been read yet?
        def read?
          @size == @data.size
        end

        # Append data to the prefix and return any extra
        def append(data)
          @data << data.slice!(0, @size - @data.size)
          return unless read?

          @payload_length = @data.unpack(@size == 2 ? 'n' : 'N').first
          data
        end

        # Length of the payload extracted from the prefix
        def payload_length
          raise RuntimeError, 'payload_length called before prefix extracted' unless read?
          @payload_length
        end

        def reset!
          @payload_length = nil
          @data = ''        
        end
      end

      def initialize(size = 2)
        @prefix = Prefix.new(size)
        @buffer = ''
      end

      # Callback for processing incoming frames
      def decode(data)
        received = []
        
        begin
          # Read data and append it to the size prefix unless it's already been read
          data = @prefix.append(data) unless @prefix.read?
          return received if data.nil? or data.empty?

          # If we've read the prefix, append the data
          @buffer << data

          # Don't do anything until we receive the specified amount of data
          return received unless @buffer.size >= @prefix.payload_length

          # Extract the specified amount of data and process it
          received << @buffer.slice!(0, @prefix.payload_length)

          # Reset the prefix and buffer since we've received a whole frame
          @prefix.reset!
          data = @buffer
          @buffer = ''
        end until data.nil? or data.empty?
        
        received
      end

      # Send a packet with a specified size prefix
      def encode(*data)
        data.reduce('') do |s, d|
          raise ArgumentError, 'packet too long for prefix length' if d.size >= 256 ** @prefix.size
          s << [d.size].pack(@prefix.size == 2 ? 'n' : 'N') << d
        end
      end
    end
  end
end