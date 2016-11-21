#!/usr/bin/ruby
require 'byebug'
load 'hfsm.rb'


class Test3 < HFSMStage
	actor "Actor1" do
		machine "Machine1" do
			state "stage1" do
				state "stage12" do
				end
			end
			state "stage2" do
			end
		end
	end
	
end

	a=Test3.new("Test3")
	a.debug_print
