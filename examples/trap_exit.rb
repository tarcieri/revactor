require 'revactor'

actor = Actor.spawn_link do
  Actor.receive do |filter|
    filter.when(:die) { raise "Aieeee!" }
  end
end

Actor.current.trap_exit = true

actor << :die
p Actor.receive { |filter| filter.when(Object) { |msg| msg } }
