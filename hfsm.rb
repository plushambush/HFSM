require 'thread'
require 'pry'
require 'byebug'
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
	attr_reader :address,:machine,:expr

	def initialize(address,expr,machine)
		super()
		@address=address
		@machine=machine
		@expr=expr
	end
	
	def matches_event?(event)
		if @address.matches?(event.to)
			begin
				context=HFSMContext.new(@machine.this_stage,@machine.this_actor,@machine,nil,event)
				return context.instance_eval(&@expr)
			rescue NoMethodError
				return false
				
			rescue ArgumentError
				return true
			end
		else
			return false
		end
	end 
	
	
	
	
end

####################################################################################################
#Очередь событий
####################################################################################################

class HFSMQueue < HFSMBase
	def initialize()
		super()  
		@queue=[]
	end
	
	def put(el)
		@queue.push(el)
	end
	
	def get
		return @queue.shift
	end
end


####################################################################################################
#Базовый объект для всех объектов, из которых конструируется HFSM дерево
#Имеет родителя (parent) и элементы (elements), классы которых которые ограничены (allowed_elements)
####################################################################################################
class HFSMDSL < HFSMObject

	
	attr_accessor :elements,:parent,:key,:group

	def initialize
		super
		@allowed_elements=[]
		@parent=nil
		@key=nil
		@elements={}
		@group=:@elements
	end
	
	def debug_print(tab=0,key='')
		puts "%s (Parent=%s)" % [(" "*tab+self.class.name()+ " " +key).ljust(60),@parent]
		@elements.each do |k,v|
			v.debug_print(tab+1,k)
		end
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
	
	def setup
		@elements.each  { |k,v|	v.setup }
	end
	
end

####################################################################################################
#Класс, который хранит в себе группу Stage-Actor-Machine-Event и умеет их сравнивать с другими такими же группами
####################################################################################################
class HFSMAddress < HFSMBase
	attr_reader :stagename,:actorname,:machinename,:eventname


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
		if @stagename!=other.stagename and @stagename!="*" and other.stagename!="*"
			return false
		end
		if @actorname!=other.actorname and @actorname!="*" and other.actorname!="*"
			return false
		end
		if @machinename!=other.machinename and @machinename!="*" and other.machinename!="*"
			return false
		end
		if @eventname!=other.eventname and @eventname!="*" and other.eventname!="*"
			return false
		end
		return true
	
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
		if @payload and @payload.has_key?(method_sym.to_s)
			return @payload[method_sym.to_s]
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
	
	def name
		return @to.to_s
	end
	
end


class HFSMHandler < HFSMDSL
	attr_accessor :longname,:expr,:block
	
	def initialize(longname,expr,&block)
		super()
		@longname=longname
		@expr=expr
		@block=block
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
		@parent
	end
	
	
	def execute(context)
		return context.instance_eval(&@block)
	end
	
	
end	



class HFSMState < HFSMDSL

  attr_reader :current_state
	
	def initialize
		super()
		@allowed_elements={HFSMHandler=>:@handlers, HFSMState=>:@states}
		@entry=nil
		@exit=nil
		@current_state=nil
		@states={}
		@handlers={}
	end
	
	def setEntry(&block)
		@entry=block
	end
	
	def setExit(&block)
		@exit=block
	end
	
	def this_stage
		@parent.this_stage
	end
	
	def this_actor
		@parent.this_actor
	end
	
	def this_machine
		@parent
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
	
	
	# Сюда входим при инициализации state
	def enter_states_chain
		enter_this_state
		if not @states.empty?
		  if @states.has_key?(InitStateName)
			@current_state=@states[InitStateName]
			@current_state.enter_state
		  else
			byebug
			raise HFSMStateException, "HFSM Error: No init state for %s" % [@key]	
		  end
		end
		  
	end
	
	def leave_states_chain
		@current_state.leave_state if @current_state
		leave_this_state
	end
	
	def enter_this_state
		if @entry
			context=HFSMContext.new(this_stage,this_actor,this_machine,this_state,HFSMEvent.create("",this_stage.name,this_actor.name,this_machine.name))
			context.instance_eval(&@entry)
		end
	end
	
	def leave_this_state
		if @exit
			context=HFSMContext.new(this_stage,this_actor,this_machine,this_state,HFSMEvent.create("",this_stage.name,this_actor.name,this_machine.name))
			context.instance_eval(&@exit)
		end
	end
	
	def newHandler(eventname,expr,&block)
		obj=HFSMHandler.new(eventname,expr,&block)
		self.addElement(eventname,obj)
	end	
	
	def createSubscriptions
		@handlers.each do |key,handler|
			this_stage.subscribe(HFSMAddress.create(handler.longname,this_stage.name,this_actor.name,this_machine.name),handler.expr,self)
		end
	end

	def setup
		super
		createSubscriptions
		(@states.values+@handlers.values).each {|v| v.setup}
	end




	
	def entry(&block)
		self.setEntry(&block)
	end

	def leave(&block)
		self.setExit(&block)
	end
	
	def on(eventname,expr=nil,&block)
		newHandler(eventname,expr,&block)
	end
	
	def state(key, &block)
		obj=HFSMState.new
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end

	def with
		Proc.new
	end
	
	
end



class HFSMMachine < HFSMState

	
	def initialize
		super()
		@allowed_elements={HFSMState=>:@states}
		

	end

	def this_stage
		@parent.this_stage
	end
	
	def this_actor
		@parent.this_actor
	end
	
	def this_machine
		self
	end

	
	def setup
		super
		reset
	end
	
	def reset
		change_state(InitStateName)
	end
	
	def state(key, &block)
		obj=HFSMState.new
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end
	
end


class HFSMActor < HFSMDSL

	
	def initialize
		super
		@allowed_elements={HFSMMachine=>:@elements}
		createDefers
	end
	
	def this_stage
		@parent.this_stage
	end
	
	def this_actor
		self
	end
	
	
	def dispatch(event)
		puts "Dispatching %s to actor %s" % [event.name,@key]
	end
	
	def self.machine(key,&block)
		deferred do
			machine(key,&block)
		end
	end

	def machine(key, &block)
		obj=HFSMMachine.new
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end
	
	
end


####################################################################################################
# Объект, обслуживаюший очередь сообщений и раздающий их Actor'ам
####################################################################################################
class HFSMStage < HFSMDSL

	
	def initialize(name)
		super()
		@allowed_elements={HFSMActor=>:@elements}
		@key=name
		@queue=HFSMQueue.new
		@subscribers=[]
		createDefers
	end


	def this_stage
		self
	end
	
	def post(event)
		puts "Posting event %s" % [event.name]
		@queue.put(event)
	end
	
	def execute
		setup
		process_queue
	end
	
	def process_queue
		while true
			event=@queue.get()
			if event
				dispatch(event)
			end
		end
	end
	
	def subscribe(address,expr,machine)
		puts "Subscribing %s to %s" % [machine,address]
		@subscribers << HFSMSubscription.new(address,expr,machine)
	end
	
	def dispatch(event)
		@subscribers.each do |sub| 
			if sub.matches_event?(event)
				sub.machine.process_event(event)
			end
		end
	end
	
	def self.actor(key, supplied=HFSMActor, &block)
		deferred do
			if supplied.class==Class
				obj=supplied.new
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
	
	def goto(statename)
		@state.request_state_change(statename)
	end
	
	def signal(longname,payload=Hash.new)
		event=HFSMEvent.create(longname,@stage.name,@actor.name,@machine.name,payload)
		@stage.post(event)
	end
	
	def reply(shortname,payload=Hash.new)
		event=HFSMEvent.from_machine(shortname,@event.from.stagename,@event.from.actorname,@event.from.machinename,payload)
		@stage.post(event)
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










