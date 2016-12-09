#!/usr/bin/ruby
require 'socket'
require 'byebug'
load  'hfsm.rb'
Thread.abort_on_exception=true

class HFSMLineMachine < HFSMMachine
	attr_accessor :buffer
	
	state "WaitingForLine" do
		enter do
			@machine.buffer=''
		end
		
		on "SocketMachine.DataReceived" do
			lines=@event.data.lines()
			lines.each do |line|
				if line =~ /\r*\n$/
					signal "LineReceived",{:line=>@machine.buffer+line.chomp}
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
	attr_accessor :outbuf

	machine "SocketMachine" do
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
				@actor.outbuf=''
				puts "TCPServer configured"
				@actor.socket.puts "Hello from TCP Server #{@actor.name}"
			end	
			
			idle do
					begin
						data,sender_addrinfo=@actor.socket.recvfrom_nonblock(2048)
						if not data.empty?
							puts "Received data: #{data}"
							signal "DataReceived",{:data => data}
						end
					rescue IO::EAGAINWaitReadable					
					end
					begin
						if not @actor.outbuf.empty?
							sent=@actor.socket.sendmsg_nonblock(@actor.outbuf)
							if sent>0
								@actor.outbuf.slice!(0,sent)
							end
						end
					rescue Errno::EPIPE
						signal "Disconnected"
					end
			end
			
		
			on "SendData" do
				@actor.outbuf+=@event.data
			end
			
			on "Disconnected" do
				goto "Stopped"
			end
			
		end
		
		state "Stopped" do
			enter do
				puts "Server stopped"
			end
		end
		
		
	end
end


class HFSMTCPLineServer < HFSMTCPServer
	machine "LineMachine",HFSMLineMachine	
end


class HFSMTCPEchoServer < HFSMTCPLineServer
	machine "EchoMachine" do
		state "Default" do
			on "LineMachine.LineReceived" do
				signal "SocketMachine.SendData", {:data=>"You said: #{@event.line}\n"}
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
					@stage.actor newactorname,HFSMTCPEchoServer
					signal "%s.SocketMachine.Configure" % [newactorname],{:client_socket=>@event.client_socket}
				end
			end
		end	
	end
end

stage=SocketStage.new "SocketStage"
stage.start