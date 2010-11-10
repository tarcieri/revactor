#--
# Copyright (C)2007-10 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require 'cool.io'
require 'case'

require 'revactor/actor'
require 'revactor/scheduler'
require 'revactor/mailbox'
require 'revactor/tcp'
require 'revactor/unix'
require 'revactor/http_client'
require 'revactor/filters/line'
require 'revactor/filters/packet'
require 'revactor/actorize'

# Tuples, they're Arrays with a === method that works!
# Tuples are the recommended container for all datagrams sent between Actors  
class Tuple < Array
  def ===(obj)
    return false unless obj.is_a? Array
    size.times { |n| return false unless self[n] === obj[n] }
    true
  end
end

# Shortcut Tuple as T
T = Tuple unless defined? T

module Revactor
  VERSION = File.read(File.expand_path('../../VERSION', __FILE__)).strip
  def self.version; VERSION; end
end

# Place Revactor modules and classes under the Actor namespace
class Actor
  TCP        = Revactor::TCP
  UNIX       = Revactor::UNIX
  Filter     = Revactor::Filter
  HttpClient = Revactor::HttpClient
end