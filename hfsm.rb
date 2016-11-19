require 'thread'
require 'pry'

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
####################################################################################################
#Базовый объект для всей HFSM
####################################################################################################
class HFSMBase
end

####################################################################################################
#Объект который имеет имя (name)
####################################################################################################
class HFSMObject < HFSMBase
	attr_accessor :name
	
	def initialize(name)
		super()
		@name=name
	end
	

end


class HFSMElements < Hash
	def values_of_match(value)
		if value=="*"
			return values
		else
			if keys.include?(value)
				return [self[key]]
			else
				return []
			end
		end
	end
end


class HFSMSubscription < HFSMBase
	attr_reader :comps,:handler

	def initialize(address,handler)
		super()
		@address=address
		@handler=handler
	end
end


class HFSMQueue < HFSMBase
	def initialize()
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
	attr_reader :elements,:parent

	def initialize(name,parent)
		super(name)
		@elements=HFSMElements.new
		@parent=parent
		@allowed_elements=[]
	end
	

	################################################################################################
	#Добавление нового элемента к elements
	#Проверяем разрешено ли добавлять элемент (проверяем класс)
	#ПРоверяем не дублируется ли имя элемента
	################################################################################################
	def addElement(name,element)
		if not @allowed_elements.include?(element.class.name)
			raise HFSMException,"HFSM Error: Class %s is not allowed as element of %s. (Allowed:%s)" % [element.class.name,self.class.name,@allowed_elements]
		end
		if @elements.has_key?(name)
			raise HFSMException, "HFSM Error: Duplicate object %s in %s %s" % [name,self.class.name,@name]
		else
			@elements[name]=element
		end
	end
	
end

####################################################################################################
#Класс, который хранит в себе группу Actor-Machine-Event и умеет их сравнивать с другими такими же группами
####################################################################################################
class HFSMAddress < HFSMBase
	attr_reader :actor,:machine,:event

	def initialize(actorname,machinename,longname)
		super()
		from_longname!(longname)
		fill_missing!(actorname,machinename)
	end	
	
	def from_longname!(longname)
		address=longname.split(".")
		from_array!(address)
	end
	
	def to_longname
		return [@actorname,@machinename,@eventname].join(".")
	end
	
	def to_array
		return [@actorname,@machinename,@eventname]
	end
	
	def from_array!(ar)
		@event=ar.pop()
		@machine=ar.pop()
		@actor=ar.pop()
	end
	
	def match?(other)
		if @actor!=other.actor and @actor!="*" and other.actor!="*"
			return false
		end
		if @machine!=other.machine and @machine!="*" and other.machine!="*"
			return false
		end
		if @event!=other.event and @event!="*" and other.event!="*"
			return false
		end
		return true
	
	end
	
	def fill_missing!(actorname,machinename)
		if not @actor
			@actor=actorname
		end
		if not @machine
			@machine=machinename
		end
	end
	
end

####################################################################################################
# Класс события, в котором есть HFSMComps и полезная нагрузка (payload)
####################################################################################################
class HFSMEvent < HFSMObject

	attr_reader :from, :to

	def initialize(actorname, machinename, longname,payload=Hash.new)
		super(longname)
		@payload=payload
		@from=HFSMAddress.new(actorname,machinename,"")
		@to=HFSMAddress.new(actorname,machinename,longname)
	end
	
	def method_missing(method_sym,arg=nil)
		if @payload.has_key?(method_sym.to_s)
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
	
end



####################################################################################################
# Объект, обслуживаюший очередь сообщений и раздающий их Actor'ам
####################################################################################################
class HFSMStage < HFSMDSL
	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMActor"]
		@queue=HFSMQueue.new
		@subscribers=[]
	end


	def stage
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
	
	def setup
		@elements.values.each {|el| el.setup}
	end
	
	def subscribe(address,handler)
		puts "Subscribing %s to %s" % [address.to_longname,handler]
		@subscribers << HFSMSubscription.new(address,handler)
	end
	
	def dispatch(event)
		@subscribers.each {|sub| sub.handler.try_handle(event)}
	end
	
	def actor(name, &block)
		obj=HFSMActor.new(name,self)
		obj.instance_eval(&block)
		self.addElement(name,obj)
	end

end


class HFSMActor < HFSMDSL
	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMMachine"]
	end
	
	def stage
		@parent.stage
	end
	
	def actor
		self
	end
	
	
	def dispatch(event)
		puts "Dispatching %s to actor %s" % [event.name,@name]
	end
	
	def setup
		@elements.values.each { |el| el.setup }
	end

	def machine(name, &block)
		obj=HFSMMachine.new(name,self)
		obj.instance_eval(&block)
		self.addElement(name,obj)
	end
	
	
end

class HFSMMachine < HFSMDSL

	attr_reader :current_state
	
	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMState"]
	end

	def stage
		@parent.stage
	end
	
	def actor
		@parent.actor
	end
	
	def machine
		self
	end

	
	def setup
		reset
	end
	
	def reset
		change_state(InitStateName,false)
	end
	
	def change_state(statename,leave_previous=true)
		if @elements.has_key?(statename)
			if leave_previous and @current_state
				@current_state.leave_state()
			end
			@current_state=@elements[statename]
			@current_state.enter_state()
		else
			raise HFSMStateException,"HFSM Error: Unknown state %s in machine %s of %s" % [statename,@name,@parent.name]
		end
	end
	
	def state(name, &block)
		obj=HFSMState.new(name,self)
		obj.instance_eval(&block)
		self.addElement(name,obj)
	end

	
end
	
class HFSMState < HFSMDSL

	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMHandler"]
		@enrty=nil
		@leave=nil
	end
	
	def setEntry(&block)
		@entry=block
	end
	
	def setLeave(&block)
		@leave=block
	end
	
	def stage
		@parent.stage
	end
	
	def actor
		@parent.actor
	end
	
	def machine
		@parent
	end
	
	def state
		self
	end
	
	def enter_state
		if @entry
			context=HFSMContext.new(actor,machine,HFSMEvent.new(actor.name,machine.name,""))
			context.instance_eval(&@entry)
		end
	end
	
	def leave_state
		if @leave
			context=HFSMContext.new(actor,machine,HFSMEvent.new(actor.name,machine.name,""))
			context.instance_eval(&@leave)
		end
	end
	
	def entry(&block)
		self.setEntry(&block)
	end

	def leave(&block)
		self.setLeave(&block)
	end
	
	def on(name,expr=nil,&block)
		obj=HFSMHandler.new(name,self,expr,&block)
		self.addElement(name,obj)
		obj.subscribe_to_events(name)
	end

	def with
		Proc.new
	end
	
end

class HFSMHandler < HFSMDSL

	def initialize(longname,parent,expr,&block)
		super(longname,parent)
		@expr=expr
		@block=block
		@allowed_elements=[]
		@addressmatch=HFSMAddress.new(actor.name,machine.name,longname)
	end

	def stage
		@parent.stage
	end
	
	def actor
		@parent.actor
	end
	
	def machine
		@parent.machine
	end
	
	def state
		@parent
	end
	
	def match_context?(context)
		if @addressmatch.match?(context.event.to)
			begin
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
	
	def try_handle(event)
		if state.name==machine.current_state.name
			context=HFSMContext.new(actor,machine,event)
			if match_context?(context)
				execute(context)
			end
		end
		
	end
	
	
	def execute(context)
		context.instance_eval(&@block)
	end
	
	def subscribe_to_events(longname)
		address=HFSMAddress.new(actor.name,machine.name,longname)
		stage.subscribe(address,self)
	end
	
end	

####################################################################################################
# Контекст, в котором выполняются обработчики событий и проверяются условия 'with'
####################################################################################################
class HFSMContext < HFSMBase
	def initialize(actor,machine,event)
		@actor=actor
		@machine=machine
		@event=event
	end
	
	def goto(statename)
		@machine.change_state(statename)
	end
	
	def signal(name,payload=Hash.new)
		event=HFSMEvent.new(@actor.name,@machine.name,name,payload)
		@actor.parent.post(event)
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



# DSL constructors	


def stage(name,&block)
	$stage=HFSMStage.new(name,nil)
	$stage.instance_eval(&block)
end










