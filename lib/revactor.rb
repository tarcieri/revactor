#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require 'rubygems'
require 'rev'
require 'case'

# This is mostly in hopes of a bright future with Rubinius
# The recommended container for all datagrams sent between
# Actors is a Tuple, defined below, and with a 'T' shortcut:
unless defined? Tuple
  # A Tuple class.  Will (eventually) be a subset of Array
  # with fixed size and faster performance, at least that's
  # the hope with Rubinius...
  class Tuple < Array; end
end

# Shortcut Tuple as T
T = Tuple unless defined? T

module Revactor
  Revactor::VERSION = '0.1.1' unless defined? Revactor::VERSION
  def self.version() VERSION end
end

require File.dirname(__FILE__) + '/revactor/actor'
require File.dirname(__FILE__) + '/revactor/server'
require File.dirname(__FILE__) + '/revactor/tcp'
require File.dirname(__FILE__) + '/revactor/behaviors/server'
require File.dirname(__FILE__) + '/revactor/filters/line'
require File.dirname(__FILE__) + '/revactor/filters/packet'

# Place Revactor modules and classes under the Actor namespace
class Actor
  Actor::TCP = Revactor::TCP unless defined? Actor::TCP
  Actor::Server = Revactor::Server unless defined? Actor::Server
  Actor::Behavior = Revactor::Behavior unless defined? Actor::Behavior
  Actor::Filter = Revactor::Filter unless defined? Actor::Filter
end