#!/usr/bin/ruby
require 'date'
load "hfsm.rb"

require 'byebug'
Thread.abort_on_exception=true
class TimerTest < HFSMStage
	actor "TT" do
		machine "TTRunner" do
			timer "TestTimer"
			state "Init" do
				enter do
					puts "Entered init state. Engaging a timer for 1 sec"
					start "TestTimer", interval:1, payload:{:starttime=>Time.new}, event:"Timer5", periodic:true
				end
				on "Timer5" do
					puts "Timer ticked after %f seconds" %[Time.now - event.starttime]
				end
			end
		end
	end
end


tt=TimerTest.new("TimerTest")
tt.start 