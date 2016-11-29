#!/usr/bin/ruby
require 'date'
load "hfsm.rb"

require 'byebug'
Thread.abort_on_exception=true
class TimerTest < HFSMStage
	actor "TT" do
		machine "TTRunner" do
			timer "TestTimer",interval:1, autostart:true, payload:{:starttime=>Time.new}, event:"Timer5", periodic:true
			state "Init" do
				enter do
					puts "Entered init state. Waiting for a timer"
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