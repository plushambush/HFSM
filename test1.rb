#!/usr/bin/ruby
require 'byebug'
load 'hfsm.rb'


class Test2 < HFSMStage
	actor "Actor1",HFSMMachine do
	end
	
end

begin 
	a=Test2.new("Test2")
	a.debug_print
rescue HFSMException
	puts "Checked @allowed_elements"
end
