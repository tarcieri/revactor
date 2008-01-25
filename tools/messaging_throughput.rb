require File.dirname(__FILE__) + '/../lib/revactor'

NTIMES=100000

begin_time = Time.now

puts "#{begin_time.strftime('%H:%M:%S')} -- Sending #{NTIMES} messages"

parent = Actor.current
child = Actor.spawn do
  (NTIMES / 2).times do
    Actor.receive do |f|
      f.when(:foo) { parent << :bar }
    end
  end
end

child << :foo
(NTIMES / 2).times do
  Actor.receive do |f|
    f.when(:bar) { child << :foo }
  end
end

end_time = Time.now
duration = end_time - begin_time
throughput = NTIMES / duration

puts "#{end_time.strftime('%H:%M:%S')} -- Finished"
puts "Duration:   #{sprintf("%0.2f", duration)} seconds"
puts "Throughput: #{sprintf("%0.2f", throughput)} messages per second"
