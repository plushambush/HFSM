#!/usr/bin/ruby
load 'hfsm.rb'

class InitStage < HFSMStage
	actor "InitActor" do
		machine "InitMachine1" do
			state "First" do
				enter do
					puts "Entered InitMachine1.First state"
				end
			end
			state "Second" do
				enter do
					puts "Entered InitMachine1.Second state"
				end
			end
			state "Third" do
				enter do
					puts "Entered InitMachine1.Third state"
				end
			end
		end
		machine "InitMachine2" do
			state "First" do
				enter do
					puts "Entered InitMachine2.First state"
				end
			end
			state "Second",initial do
				enter do
					puts "Entered InitMachine2.Second state"
				end
			end
			state "Third" do
				enter do
					puts "Entered InitMachine2.Third state"
				end
			end
		end
		machine "InitMachine3" do
			state "First" do
				enter do
					puts "Entered InitMachine3.First state"
				end
			end
			state "Second" do
				enter do
					puts "Entered InitMachine3.Second state"
				end
			end
			state "Init" do
				enter do
					puts "Entered InitMachine3.Init state"
				end
			end
		end
		
		
	end
end


stage=InitStage.new "InitStage"
stage.start
