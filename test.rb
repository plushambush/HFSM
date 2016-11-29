#!/usr/bin/ruby
load "hfsm.rb"

class TestSender < HFSMActor
	machine "TestSenderMachine" do
		
			state "Init" do
				enter do
					puts "Entered Test"
					puts "[Init state] check passed"
					goto "Test1"
				end
			end
				
			state "Test1" do
				enter do
					puts "Test 1 Started"
					puts "Signalling local event 'Test1Signal1'"
					signal "Test1Signal1"
				end
				leave do
					puts "Test 1 Passed"
				end
				
				on "Test1Signal1" do
					puts "Received local event 'Test1Signal1'"
					signal "Test1SignalReceived"
				end
				
				on "Test1SignalReceived" do
					goto "Test2"
				end
			end
				
			state "Test2" do
				enter do
					puts "Test 2 Started"
					puts "Signalling machine local event 'TestSenderMachine.Signal2'"
					signal "TestSenderMachine.Signal2"
				end
				leave do
					puts "Test 2 Passed"
				end
				
				on "TestSenderMachine.Signal2" do
					puts "Received machine local event 'TestSenderMachine.Signal2'"
					signal "Test2SignalReceived"
				end
				
				on "Test2SignalReceived" do
					goto "Test3"
				end
			end
				
			state "Test3" do
				enter do
					puts "Test 3 Started"
					puts "Signalling actor local event 'TestSender.TestSenderMachine.Signal3'"
					signal "TestSender.TestSenderMachine.Signal3"
				end			
				leave do
					puts "Test 3 passed"
				end
				
				on "TestSender.TestSenderMachine.Signal3" do
					puts "Received actor local event 'TestSender.TestSenderMachine.Signal3'"
					signal "Test3SignalReceived"
				end
				
				on "Test3SignalReceived" do
					goto "Test4"
				end
			end
				
			state "Test4" do
				enter do
					puts "Test 4 Started"
					puts "Signalling stage local event 'TestStage.TestSender.TestSenderMachine.Signal4'"
					signal "TestStage.TestSender.TestSenderMachine.Signal4"
				end
				leave do
					puts "Test 4 passed"
				end
				
				on "TestStage.TestSender.TestSenderMachine.Signal4" do
					puts "Received stage local event 'TestStage.TestSender.TestSenderMachine.Signal4'"
					signal "Test4SignalReceived"
				end
				
				on "Test4SignalReceived" do
					goto "Test5"
				end
			end
			
			state "Test5" do
				enter do
					puts "Test 5 Started"
					puts "Signalling to the machine on the other actor 'TestStage.TestReceiver.TestReceiverMachine.Signal5'"
					signal "TestStage.TestReceiver.TestReceiverMachine.Signal5"
				end
				
				leave do
					puts "Test 5 Passed"
				end
				
				on "Test5SignalReceived" do
					goto "Test6"
				end
			end
			
			state "Test6" do
				enter do 
					puts "Test 6 started: Nested states"
					puts "Signalling Signal6 which should be received by child state"
					signal "Signal6"
				end
				
				leave do
					puts "Test 6 passed"
				end
				
				state "Init" do
					on "Signal6" do
						puts "Signal 6 received in substate Test6.1"
						reply "Signal6Received"
					end
				end
				
				on "Signal6" do
					puts "FAIL: Received signal for nested state in parent state"
				end
				
				on "Signal6Received" do
					goto "TestEnd"
				end
				
			end
			
			
			state "TestEnd" do
				enter do
					puts "All tests passed"
				end
			end
		end
	end


class TestStage < HFSMStage
	actor "TestSender",TestSender
	actor "TestReceiver" do
		machine "InterceptMachine" do
			state "Init" do
				enter do
					puts "Event interceptor started"
				end
				on "*.*.*.*" do
					puts "Intercepted event %s" % [event.to]
				end
			end
		end
	
		machine "TestReceiverMachine" do
			state "Init" do
				enter do
					puts "TestReceiverMachine started"
				end
				
				on "Signal5" do
					puts "Received 'TestStage.TestReceiver.TestReceiverMachine.Signal5'"
					reply "Test5SignalReceived"
				end
			end
			
		end
	end
end

test=TestStage.new("TestStage")
test.debug_print
test.start
