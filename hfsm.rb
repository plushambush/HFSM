require 'pp'

InitStateName="Init"

####################################################################################################
#Классы исключений
####################################################################################################
class HFSMException < Exception
end

class HFSMMachineException < HFSMException
end

class HFSMDuplicateMachineException < HFSMMachineException
end

class HFSMStateException < HFSMException
end

class HFSMDuplicateStateException < HFSMStateException
end

class HFSMHandlerException < HFSMException
end

class HFSMDuplicateHandlerException < HFSMHandlerException
end

class HFSMUnknownEventException < HFSMHandlerException
end

class HFSMActorException < HFSMException
end

class HFSMTimerException < HFSMException
end

####################################################################################################
#Базовый объект для всей HFSM
####################################################################################################
class HFSMBase

end

####################################################################################################
#Объект который имеет имя (label)
####################################################################################################
class HFSMObject < HFSMBase
	attr_accessor :name

	def initialize(name='')
		super()
		@name=name
	end
end

####################################################################################################
#Объект, содержащий в себе данные подписки handler на address
####################################################################################################

class HFSMSubscription < HFSMBase
	attr_reader :address,:subscriber,:expr

	def initialize(address,subscriber,expr=nil)
		super()
		@address=address
		@subscriber=subscriber
		@expr=expr
	end
	
	def matchesReceiver?(event)
		return @address.matches?(event.to)
	end
	
	def matchesExpr?(event)
		begin
			context=HFSMContext.new(@subscriber.this_stage,@subscriber.this_actor,@subscriber.this_machinee,@subscriber.this_state,event)
			return context.instance_eval(&@expr)
		rescue NoMethodError
			return false
		rescue ArgumentError
			return true
		end
		return false
	end

end


####################################################################################################
#Базовый объект для всех объектов, из которых конструируется HFSM дерево
#Имеет родителя (parent) и элементы (elements), классы которых которые ограничены (allowed_elements)
####################################################################################################
class HFSMDSL < HFSMObject

	
	attr_accessor :elements,:parent,:key,:group

	def initialize(name)
		super
		@allowed_elements={}
		@parent=nil
		@key=nil
		@elements={}
	end
	
	def each_element
		@allowed_elements.values.each do |val|
			if self.instance_variable_defined?(val)
				self.instance_variable_get(val).each do |k,v|
					yield k,v
				end
			end
		end
	end
	
	def debug_print(tab=0,key='')
		puts "%s (Parent=%s)" % [(" "*tab+self.class.name()+ " " +key).ljust(60),@parent]
		each_element do |k,v|
			v.debug_print(tab+1,k)
		end
	end
	
	def this_stage
		@parent.this_stage
	end
	
	def this_actor
		@parent.this_actor
	end
	
	def this_machine
		@parent.this_machine
	end
	
	def this_state
		@parent.this_state
	end
	
	###########################################################################################
	# Методы для отложенной инициализации инстанса
	###########################################################################################
	@@_defers={}

	# Добавляем процедуру отложенной инициализации в список
	# Поскольку все изменения, которые делают в классовых переменных потомки, производятся в базовом классе
	# нам приходится хранить процедуры инициализации в общем хэше, ключом к которому является имя класса
	#
	def self.deferred(&block)
		if not @@_defers.has_key?(name())
			@@_defers[name()]=Array.new
		end
		@@_defers[name()] << block
	end

	# Производит инициализацию объекта target отложенными объектами данного класса
	def self.createDefersIn(target)
		if @@_defers and @@_defers.has_key?(name())
			@@_defers[name()].each do |block|
				target.instance_eval(&block)
			end
		end
	end
	# Отложенная Инициализация. Пробегаем по всем родителям класса, которые поддерживают отложенную инициализацию,
	# и инициализируем их
	def createDefers
		self.class.ancestors.reverse.each do |ancestor|
			if ancestor.methods.include? :createDefersIn
				ancestor.createDefersIn(self)
			end
		end
	end

	

	def findStorage(element)
		store_as = (@allowed_elements.keys & element.class.ancestors)
		if not store_as.empty?
			return @allowed_elements[store_as[0]]
		else
			return nil
		end
	end


	################################################################################################
	#Добавление нового элемента к elements
	#Проверяем разрешено ли добавлять элемент (проверяем класс)
	#ПРоверяем не дублируется ли имя элемента
	################################################################################################
	def addElement(key,element)
		storage=findStorage(element)
		if not storage
			raise HFSMException,"HFSM Error: Class %s is not allowed as element of %s. (Allowed:%s)" % [element.class.name,self.class.name,@allowed_elements.keys]
		end
		if not self.instance_variable_defined?(storage)
			self.instance_variable_set(storage,Hash.new)
		end
		self.instance_variable_get(storage)[key]=element
		element.addedTo(self,key)
	end
	
	def addedTo(parent,key)
	  @parent=parent
	  @key=key
	end
	
	def _setup
	end
	
	def setup
		each_element  { |k,v|	v.setup }
		_setup
	end
	
	def _run
	end
	
	def run
		each_element { |k,v|  v.run }
		_run
	end
	
end

####################################################################################################
#Класс, который хранит в себе группу Stage-Actor-Machine-Event и умеет их сравнивать с другими такими же группами
####################################################################################################
class HFSMAddress < HFSMBase
	attr_reader :stagename,:actorname,:machinename,:eventname


	def self.simplematch?(a,b)
		return (not ((a != "*") and (b != "*") and (a != b)))
	end

	def initialize
	  super
	end

	def self.create(longname,stagename,actorname,machinename)
		e=HFSMAddress.new
		e.from_longname!(longname)
		e.fill_missing!(stagename,actorname,machinename)
		return e
	end	
	
	
	def to_s
		return [@stagename,@actorname,@machinename,@eventname].join(".")
	end
	
	
	def from_longname!(longname)
		address=longname.split(".")
		from_array!(address)
	end
	
	
	def to_array
		return [@stagename,@actorname,@machinename,@eventname]
	end
	
	def from_array!(ar)
		@eventname=ar.pop()
		@machinename=ar.pop()
		@actorname=ar.pop()
		@stagename=ar.pop()
	end
	
	def matches?(other)
		return  (HFSMAddress.simplematch?(@stagename,other.stagename) and
				HFSMAddress.simplematch?(@actorname,other.actorname) and
				HFSMAddress.simplematch?(@machinename,other.machinename) and
				HFSMAddress.simplematch?(@eventname,other.eventname))
	
	end
	
	def fill_missing!(stagename,actorname,machinename)
		if not @stagename
			@stagename=stagename
		end
		if not @actorname
			@actorname=actorname
		end
		if not @machinename
			@machinename=machinename
		end
	end
	
end

####################################################################################################
# Класс события, в котором есть HFSMComps и полезная нагрузка (payload)
####################################################################################################
class HFSMEvent < HFSMObject

	attr_accessor :from, :to, :payload

	def self.create(longname,stagename,actorname,machinename,payload=Hash.new)
		e=HFSMEvent.new
		e.payload=payload
		e.from=HFSMAddress.create("",stagename,actorname,machinename)
		e.to=HFSMAddress.create(longname,stagename,actorname,machinename)
		return e
	end
  
	def initialize()
		super
		@from=nil
		@to=nil
		@payload=nil
	end
	
	def method_missing(method_sym,arg=nil)
		if @payload and @payload.has_key?(method_sym)
			return @payload[method_sym]
		else
			raise NoMethodError,"HFSM Error: Attribute %s not found in event %s" % [method_sym,name]
		end
	end
	
	def respond_to?(name,all=false)
		if super(name,all)
			return true
		else
			return @payload.has_key?(name.to_s)
		end
	end
	
end


class HFSMHandler < HFSMDSL
	attr_accessor :block,:longname,:expr
	
	def initialize(longname,expr,&block)
		super(longname)
		@longname=longname
		@expr=expr
		@block=block
	end

	def execute(context)
		result=context.instance_eval(&@block)
		#TODO: handler exit codes
		return (not (result==:UP))
	end
	
	
	def _setup
		@match=HFSMAddress.create(@longname,this_stage.name,this_actor.name,this_machine.name)		
	end
	
	def receiveFromUpstream(event)
		dispatchEvent(event)
	end
	
	def dispatchEvent(event)
		processed=false
		if event.to.matches?(@match)
			context=HFSMContext.new(this_stage,this_actor,this_machine,this_state,event)		
			if @expr
				if context.exprMatch?(&@expr)
					processed=execute(context)
				else
					processed=false
				end
			else
				processed=execute(context)
			end
		else
			processed=false
		end
		return processed
	end
	
end	



class HFSMState < HFSMDSL

  attr_reader :current_state
	
	def initialize(name)
		super
		@allowed_elements={HFSMHandler=>:@handlers, HFSMState=>:@states, HFSMTimer=>:@timers}
		@enter=nil
		@exit=nil
		@current_state=nil
		@initial_state=nil
		@states={}
		@handlers={}
		@timers={}
	end
	
	def setEnter(&block)
		@enter=block
	end
	
	def setExit(&block)
		@exit=block
	end
	
	def this_state
		self
	end
	
	def have_parent_state
	  return (not (@parent.class.ancestors & [HFSMState]).empty?)
	end

	# сюда входим при смене state по результатам работы обработчика
	def request_state_change(statename)
		if have_parent_state
			@parent.change_state(statename)
		else
			raise HFSMStateException, "HFSM Error: State not found [%s]" % [statename]
		end	  
	end
	

	def change_state(statename)
		if not @states.empty? and @states.has_key?(statename)
			switch_to_state(@states[statename])
		else
			if have_parent_state
				@parent.change_state(statename)
			else
				raise HFSMStateException, "HFSM Error: State not found [%s]" % [statename]
			end
		end
	end
	
	def switch_to_state(state)
		@current_state.leave_states_chain if @current_state
		@current_state=state
		@current_state.enter_states_chain
	end
	
	
	def enter_initial_state
		if not @states.empty?
		  if @initial_state
			@current_state=@initial_state
			@current_state.enter_states_chain
		  else
			raise HFSMStateException, "HFSM Error: No init state for %s" % [@key]	
		  end	
		end
	end
	
	# Сюда входим при инициализации state
	def enter_states_chain
		enter_this_state
		enter_initial_state
		  
	end
	
	def leave_states_chain
		@current_state.leave_states_chain if @current_state
		leave_this_state
	end
	
	def enter_this_state
		if @enter
			context=HFSMContext.new(this_stage,this_actor,this_machine,this_state,HFSMEvent.create("",this_stage.name,this_actor.name,this_machine.name))
			context.instance_eval(&@enter)
		end
		start_timers
	end
	
	def leave_this_state
		if @exit
			context=HFSMContext.new(this_stage,this_actor,this_machine,this_state,HFSMEvent.create("",this_stage.name,this_actor.name,this_machine.name))
			context.instance_eval(&@exit)
		end
		stop_timers
	end
	
	def stop_timers
		@timers.each {|k,timer| timer.stop}
	end
	
	def start_timers
		@timers.each {|k,timer| timer.start if timer.autostart}
	end
	
	def newHandler(eventname,expr,&block)
		obj=HFSMHandler.new(eventname,expr,&block)
		self.addElement(eventname,obj)
	end	


	def subscribeMeTo(address,subscriber,expr)
		@parent.subscribeMeTo(address,subscriber,expr)
	end
	
	def createSubscriptions
		@handlers.each do |key,handler|
			subscribeMeTo(HFSMAddress.create(handler.longname,this_stage.name,this_actor.name,this_machine.name),handler,handler.expr)
		end
	end
	
	def dispatchEvent(event)
		processed=false
		if @current_state
			processed=@current_state.receiveFromUpstream(event)
		end
		if not processed
			processed=dispatchEventLocal(event)
		end
		return processed
	end
	
	def receiveFromUpstream(event)
		dispatchEvent(event)
	end
	
	def dispatchEventLocal(event)
		processed=false
		@handlers.each do |key,handler|
			processed=handler.receiveFromUpstream(event)
			return processed if processed
		end
		return processed
	end

	def _setup
		createSubscriptions
	end

	def enter(&block)
		self.setEnter(&block)
	end

	def leave(&block)
		self.setExit(&block)
	end
	
	def on(eventname,expr=nil,&block)
		newHandler(eventname,expr,&block)
	end
	
	def state(key, initial=false, &block)
		obj=HFSMState.new(key)
		if initial or  key===InitStateName or @states.empty?
			@initial_state=obj
		end
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end

	def with
		Proc.new
	end
	
	def timer(key,interval:nil,periodic:false,autostart:false,event:nil,payload:nil)
		obj=HFSMTimer.new(key,interval,periodic,autostart,event,payload)
		self.addElement(key,obj)
	end
	
	def self.initial
		true
	end
	
	def initial
		true
	end
		
end



class HFSMMachine < HFSMState
	attr_reader :timers

	
	def initialize(name)
		super
		@allowed_elements={HFSMState=>:@states, HFSMTimer=>:@timers}
	end

	def this_machine
		self
	end
	
	def subscribeMeTo(address,subscriber,expr)
		@parent.subscribeMeTo(address,self,expr)
	end
	
	
	def _run
		reset
	end
	
	def reset
		enter_initial_state
		start_timers
	end
	
	
#	def state(key, &block)
#		obj=HFSMState.new(key)
#		self.addElement(key,obj)
#		obj.instance_eval(&block)		
#	end
	
end


class HFSMGenericEventProcessor < HFSMDSL
	def initialize(name)
		super
		@queue=Queue.new
		@subscribers=[]
	end
	
	##############################################################################
	# Обработка очереди
	#############################################################################
	def subscribeMeTo(address,subscriber,expr=nil)
		@subscribers << HFSMSubscription.new(address,subscriber,expr)
	end
	
	def	 receiveFromUpstream(event)
		@queue.enq(event)
	end
	
	def	 receiveFromDownstream(event)
		@queue.enq(event)
	end
	
	
	def processQueue(blocking=true)
		if blocking or (not @queue.empty?)
			event=@queue.deq((not blocking))
			dispatchEvent(event)
		end
	end
	
	def dispatchEvent(event)
		visited=[]
		@subscribers.each do |subs|
			if not visited.include? subs.subscriber.name
				if subs.matchesReceiver?(event)
					if ((not @expr) or (@expr and subs.matchesExpr?(event)))
						subs.subscriber.receiveFromUpstream(event)
						visited << subs.subscriber.name
					end
				end
			end
		end
	end

	def _run
		while true
			processQueue
		end
	end

	
	
	##############################################################################
	
	
end

class HFSMActor < HFSMGenericEventProcessor
	
	def initialize(name)
		super
		@allowed_elements={HFSMMachine=>:@elements}
		createDefers
	end
	
	def this_actor
		self
	end
	
	def subscribeMeTo(address,subscriber,expr)
		super
		@parent.subscribeMeTo(address,self,expr)
	end
	
	
	def self.machine(key,&block)
		deferred do
			machine(key,&block)
		end
	end

	def machine(key, &block)
		obj=HFSMMachine.new(key)
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end
	
	
	def idle
		Thread.pass
	end

	def _run
		Thread.new do
			while true do
				processQueue(blocking=false)
				idle
			end
		end
	end

end


####################################################################################################
# Объект, обслуживаюший очередь сообщений и раздающий их Actor'ам
####################################################################################################
class HFSMStage < HFSMGenericEventProcessor
	
	def initialize(name)
		super
		@allowed_elements={HFSMActor=>:@elements}
		@key=name
		createDefers
	end

	def this_stage
		self
	end
	
	
	def start
		setup
		run
	end
	
	def self.actor(key, supplied=HFSMActor, &block)
		deferred do
			if supplied.class==Class
				obj=supplied.new(key)
			else
				raise HFSMException,"HFSM Error: Instantiated class %s in deferred constructor" % [supplied]
			end
			self.addElement(key,obj)
			if block
				obj.instance_eval(&block)
			end
			
		end
	end

end

	

####################################################################################################
# Контекст, в котором выполняются обработчики событий и проверяются условия 'with'
####################################################################################################
class HFSMContext < HFSMBase
	def initialize(stage,actor,machine,state,event)
		@stage=stage
		@actor=actor
		@machine=machine
		@state=state
		@event=event
	end

	def exprMatch?(&expr)
		begin
			return self.instance_eval(&expr)
		rescue NoMethodError
			return false
		rescue ArgumentError
			return true
		end
		return false
	end
	
	def goto(statename)
		@state.request_state_change(statename)
	end
	
	def signal(longname,payload=Hash.new)
		event=HFSMEvent.create(longname,@stage.name,@actor.name,@machine.name,payload)
		@stage.receiveFromDownstream(event)
	end
	
	def reply(shortname,payload=Hash.new)
		event=HFSMEvent.create(shortname,@event.from.stagename,@event.from.actorname,@event.from.machinename,payload)
		@stage.receiveFromDownstream(event)
	end
	
	def start(timer,interval:nil,periodic:false,event:nil,payload:nil)
		if @machine.timers.has_key?(timer)
			@machine.timers[timer].start(interval,periodic,event,payload)
		else
			raise HFSMTimerException, "HFSM Error: Timer [%s] not found" % [timer]
		end
	end
	
	def stop(timer)
		if @machine.timers.has_key?(timer)	
			@machine.timers[timer].stop
		else
			raise HFSMTimerException, "HFSM Error: Timer [%s] not found" % [timer]
		end
			
	end
		
	def restart(timer)
		if @machine.timers.has_key?(timer)	
			@machine.timers[timer].restart
		else
			raise HFSMTimerException, "HFSM Error: Timer [%s] not found" % [timer]
		end
			
	end
	
	def reset
		@machine.reset
	end
	
	def actor
		@actor.name
	end
	
	def machine
		@machine.name
	end
	
	def event
		@event
	end
end

class HFSMTimer < HFSMDSL
	attr_reader :autostart
	
	def initialize(name,interval=nil,periodic=false,autostart=false,event=nil,payload=nil)
		super(name)
		@name=name
		@autostart=autostart
		@default_interval=interval
		@default_event=event
		@default_payload=payload
		@default_periodic=periodic
		@thread=nil		
	end
	
	def start(interval=nil,periodic=false,event=nil,payload=nil)
		if (not interval) and (not @default_interval)
			raise HFSMTimerException,"HFSM Error: Starting timer [%s] without interval set" % [@name]
		end
		
		def first_defined(ar)
			ar.each do |elem|
				return elem if elem
			end
			return nil
		end
		
		@current_interval=first_defined [interval,@default_interval]
		@current_event=first_defined [event,@default_event,@name]
		@current_payload=first_defined [payload,@default_payload]
		@current_periodic=first_defined [periodic,@default_periodic]
		
		@thread=Thread.new do
			begin
				sleep @current_interval
				e=HFSMEvent.create(@current_event,this_stage.name,this_actor.name,this_machine.name,@current_payload)
				this_stage.receiveFromDownstream(e)
			end while @current_periodic
			
		end
	end
	
	def stop
		@thread.kill if @thread
	end
	
	def restart
		stop
		start(@current_interval,@current_periodic,@current_event,@current_payload)
	end
end