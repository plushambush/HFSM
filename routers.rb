load  "hfsm.rb"

class HFSMPeer
	
	def initialize
		@queue=HFSMQueue.new
		@peermutex=Mutex.new
		@peers=
		
	end
	
	# Вызывается Peer'ом для того, чтобы соединиться
	def connectMe(peer)
	end
	# Вызывается Peer'ом для того, чтобы разъединиться
	def disconnectMe(peer)
	end
	
	# Вызывается Peer'ом для того, чтобы подписаться на событие
	def subscribeMeTo(peer,address)
	end
	
	# Вызывается Peer'ом для того, чтобы отписаться от события
	def unsubscribeMeFrom(peer,address)
	end
	
	# Вызывается Peer'ом для того, чтобы передать событие, предназначенное для этого пира
	def receiveFromMe(event)
	end
	
	# Один раунд обработки внутренней очереди событий
	def processQueue
	end
	
	# Основной метод, работающий внутри Thread'а
	def run
	end
	
end

