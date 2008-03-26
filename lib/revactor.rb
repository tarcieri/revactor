#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require 'rev'
require 'case'

# This is mostly in hopes of a bright future with Rubinius
# The recommended container for all datagrams sent between
# Actors is a Tuple, defined below, and with a 'T' shortcut:
unless defined? Tuple
  # A Tuple class.  Will (eventually) be a subset of Array
  # with fixed size and faster performance, at least that's
  # the hope with Rubinius...
  class Tuple < Array
    def ===(obj)
      return false unless obj.is_a? Array
      size.times { |n| return false unless self[n] === obj[n] }
      true
    end
  end
end

# Shortcut Tuple as T
T = Tuple unless defined? T

module Revactor
  Revactor::VERSION = '0.2.0' unless defined? Revactor::VERSION
  def self.version() VERSION end
end

%w{
  actor scheduler mailbox tcp http_client
  filters/line filters/packet actorize
}.each do |file|
  require File.dirname(__FILE__) + '/revactor/' + file
end

# Place Revactor modules and classes under the Actor namespace
class Actor
  Actor::TCP = Revactor::TCP unless defined? Actor::TCP
  Actor::Filter = Revactor::Filter unless defined? Actor::Filter
  Actor::HttpClient = Revactor::HttpClient unless defined? Actor::HttpClient
end
