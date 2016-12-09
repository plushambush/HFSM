#!/usr/bin/ruby
require 'socket'
require 'byebug'
load  'hfsm.rb'
Thread.abort_on_exception=true

class HFSMLineMachine < HFSMMachine
	attr_accessor :buffer
	
	state "Main" do
		enter do
			@buffer=''
		end
		
		on "DataReceived" do
			@event.data.lines.each do |line|
				if line.end_with?("\n")
					signal "LineReceived",{:line=>@machine.buffer+line}
					@machine.buffer=''
				else
					@machine.buffer+=line
				end
			end
		end
		
	end
end



class HFSMTCPServer < HFSMActor
	attr_accessor :socket
	machine "LineMachine",HFSMLineMachine
	machine "Main" do
		state "Unconfigured" do
			enter do
				puts "TCPServer started in unconfigured state"
			end
			on "Configure" do
				@actor.socket=@event.client_socket
				goto "Active"
			end
		end
		
		state "Active" do
			enter do
				puts "TCPServer configured"
				@actor.socket.puts "Hello from TCP Server #{@actor.name}"
			end	
		end
	end
end




class HFSMTCPServerFabric < HFSMActor
	attr_accessor :socket
	
	machine "Listener" do
		state "Idle" do
			enter do
				puts "Entered Idle state"
			end
		end	
		
		state "Accepting",initial do
			enter do
				puts "Entered Accepting state"
				socket=Socket.new(Socket::AF_INET,Socket::SOCK_STREAM,0)
				socket.bind(Addrinfo.tcp("127.0.0.1",2222))
				socket.listen(5)
				@actor.socket=socket
			end
			
			leave do
				puts "Closing socket"
				@actor.socket.close
			end
			
			idle do
				begin
					if not @actor.socket.closed?
						client_socket, client_addrinfo=@actor.socket.accept_nonblock
						signal "Connected",{:client_socket=>client_socket,:client_addrinfo=>client_addrinfo}
					end
				rescue IO::EAGAINWaitReadable
				end
			end
				
		end
	end

end




class SocketStage < HFSMStage
	actor "SocketActor",HFSMTCPServerFabric do
		machine "Fabric" do
			state "WaitConnect" do
				on "Listener.Connected" do
					puts "Fabric: detected connection on socket #{@event.client_socket}"
					newactorname="TCPServer%s" % [@event.client_socket.to_s]
					@stage.actor newactorname,HFSMTCPServer
					signal "%s.Main.Configure" % [newactorname],{:client_socket=>@event.client_socket}
				end
			end
		end	
	end
end

stage=SocketStage.new "SocketStage"
stage.start