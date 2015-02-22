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

	def initialize(name,handler)
		super()
		@comps=HFSMComps.new(name)
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
class HFSMComps < HFSMBase
	attr_reader :actor,:machine,:event

	def initialize(actor=nil,machine=nil,event)
		super()
		if actor 
			@actor=actor.name
		end
		if machine
				@machine=machine.name
		end
		@event=event.name
	end	
	
	def initialize(name)
		super()
		from_name!(name)
	end 	

	def from_name!(name)
		comps=name.split(".")
		from_array!(comps)
	end
	
	def to_name
		return ".".join([@actor,@machine,@event])
	end
	
	def to_array
		return [@actor,@machine,@event]
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
		if @event!=other.event
			return false
		end
		return true
	
	end
	
	def fill_missing!(actor,machine)
		if not @actor
			@actor=actor.name
		end
		if not @machine
			@machine=machine.name
		end
	end
	
end

####################################################################################################
# Класс события, в котором есть HFSMComps и полезная нагрузка (payload)
####################################################################################################
class HFSMEvent < HFSMObject

	attr_reader :comps

	def initialize(name,payload=Hash.new)
		super(name)
		@payload=payload
		@comps=HFSMComps.new(name)
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
	
	def fill_missing!(actor,machine)
		@comps.fill_missing!(actor,machine)
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
	
	def subscribe(event,handler)
		puts "Subscribing %s to %s" % [event,handler]
		@subscribers << HFSMSubscription.new(event,handler)
	end
	
	def dispatch(event)
		@subscribers.each do |sub|
			if sub.comps.match?(event.comps)
				sub.handler.handle(event)
			end
		end
	end
end


class HFSMActor < HFSMDSL
	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMMachine"]
	end
	
	def dispatch(event)
		puts "Dispatching %s to actor %s" % [event.name,@name]
	end
	
	def setup
		@elements.values.each { |el| el.setup }
	end
end

class HFSMMachine < HFSMDSL
	def initialize(name,parent)
		super(name,parent)
		@allowed_elements=["HFSMState"]
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
				@current_state.leave()
			end
			@current_state=@elements[statename]
			@current_state.enter()
		else
			raise HFSMStateException,"HFSM Error: Unknown state %s in machine %s of %s" % [statename,@name,@parent.name]
		end
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
	
	def machine
		return @parent
	end
	
	def actor
		return machine.parent
	end
	
	def stage
		return actor.parent
	end
	
	def enter
		if @entry
			context=HFSMContext.new(actor,machine,nil)
			context.instance_eval(&@entry)
		end
	end
	
	def leave
		if @leave
			context=HFSMContext.new(actor,machine,nil)
			context.instance_eval(&@leave)
		end
	
	
	end
	
	def handle(event)
		context=HFSMContext.new(actor,machine,event)
		@elements.each do |el|
			if el.match_context?(comps)
				el.handle(context)
			end
		end
	end
	
end

class HFSMHandler < HFSMDSL
	def initialize(name,parent,expr,&block)
		super(name,parent)
		@expr=expr
		@block=block
		@allowed_elements=[]
		@target=HFSMComps.new(name)
	end
	
	def match_context?(context)
		if @target.match?(context.e.comps)
			begin
				return context.instance_eval(&@expr)
			rescue NoMethodError
				return false
			end
		else
			return false
		end
	end 
	
	def handle(event)
		
	end
	
	
	def execute(context)
		context.instance_eval(&@block)
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
		event=HFSMEvent.new(name,payload)
		event.fill_missing!(@actor,@machine)
		@actor.parent.post(event)
	end
	
	def reset
		@machine.reset
	end
	
	def a
		@actor
	end
	
	def m
		@machine
	end
	
	def e
		@event
	end
end



# DSL constructors	


def stage(name,&block)
	$stage=HFSMStage.new(name,nil)
	$stage.instance_eval(&block)
end

def actor(name, &block)
	obj=HFSMActor.new(name,self)
	obj.instance_eval(&block)
	self.addElement(name,obj)
end

def machine(name, &block)
	obj=HFSMMachine.new(name,self)
	obj.instance_eval(&block)
	self.addElement(name,obj)
end

def state(name, &block)
	obj=HFSMState.new(name,self)
	obj.instance_eval(&block)
	self.addElement(name,obj)
end

def on(name,expr=nil,&block)
	obj=HFSMHandler.new(name,self,expr,&block)
	self.addElement(name,obj)
	self.stage.subscribe(name,obj)
end

def entry(&block)
	self.setEntry(&block)
end

def leave(&block)
	self.setLeave(&block)
end

def with
	Proc.new
end


stage "Stage1" do
	actor "Actor1" do
		machine "Machine1" do
		
			state "Init" do
				entry do
					puts "Entered Init entry on Machine1"
					signal "Event2",{"value"=>1}
				end
				
				leave do
					puts "Left Init state on Machine1"
				end
				
				on "Event2" do
					puts "Got Event2 on Machine1"
				end
				
			end
		end
		
		machine "Machine2" do
			state "Init" do
				on "Actor1.Machine1.Event2",with {e.value==2} do
					puts "caught Actor1.Machine1.Event2 in Machine2"
				end
				
			end
		end
		
	end	
end

$stage.execute

