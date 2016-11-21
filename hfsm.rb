require 'thread'
require 'pry'
require 'byebug'
require 'pp'


InitStateName="Init"

####################################################################################################
#������ ����������
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
#������� ������ ��� ���� HFSM
####################################################################################################
class HFSMBase
end

####################################################################################################
#������ ������� ����� ��� (name)
####################################################################################################
class HFSMObject < HFSMBase
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
#������� ������ ��� ���� ��������, �� ������� �������������� HFSM ������
#����� �������� (parent) � �������� (elements), ������ ������� ������� ���������� (allowed_elements)
####################################################################################################
class HFSMDSL < HFSMObject
	@@allowed_elements=[]
	
	attr_accessor :elements,:parent,:key

	def initialize
		super
		@parent=nil
		@elements={}
	end
	
	def debug_print(tab=0,key='')
		puts "%s (Parent=%s)" % [(" "*tab+self.class.name()+ " " +key).ljust(60),@parent]
		@elements.each do |k,v|
			v.debug_print(tab+1,k)
		end
	end
	
	###########################################################################################
	# ������ ��� ���������� ������������� ��������
	###########################################################################################
	@@_defers=Hash.new

	def self._defers
		if @@_defers.has_key?(name())
			return @@_defers[name()]
		else
			nil
		end
	end

	# ��������� ��������� ���������� ������������� � ������
	# ��������� ��� ���������, ������� ������ � ��������� ���������� �������, ������������ � ������� ������
	# ��� ���������� ������� ��������� ������������� � ����� ����, ������ � �������� �������� ��� ������
	#
	def self.deferred(&block)
		if not @@_defers.has_key?(name())
			@@_defers[name()]=Array.new
		end
		@@_defers[name()] << block
	end

	# ���������� ������������� ������� target ����������� ��������� ������� ������
	def self.createMyDefersIn(target)
		if _defers
			_defers.each do |block|
				target.instance_eval(&block)
			end
		end
	end
	# ���������� �������������. ��������� �� ���� ��������� ������, ������� ������������ ���������� �������������,
	# � �������������� ��
	def createDefers
		self.class.ancestors.reverse.each do |ancestor|
			if ancestor.methods.include? :createMyDefersIn
				ancestor.createMyDefersIn(self)
			end
		end
	end

	


	################################################################################################
	#���������� ������ �������� � elements
	#��������� ��������� �� ��������� ������� (��������� �����)
	#��������� �� ����������� �� ��� ��������
	################################################################################################
	def addElement(key,element)
		if not (@@allowed_elements & element.class.ancestors)
			raise HFSMException,"HFSM Error: Class %s is not allowed as element of %s. (Allowed:%s)" % [element.class.name,self.class.name,@@allowed_elements]
		end
		if @elements.has_key?(key)
			raise HFSMException, "HFSM Error: Duplicate object %s in %s %s" % [key,self.class.name,self.key]
		else
			@elements[key]=element
			element.parent=self
			element.key=key
		end
	end
	
	
	def setup
		@elements.each  { |k,v|	v.setup }
	end
	
end

####################################################################################################
#�����, ������� ������ � ���� ������ Stage-Actor-Machine-Event � ����� �� ���������� � ������� ������ �� ��������
####################################################################################################
class HFSMAddress < HFSMBase
	attr_reader :stagename,:actorname,:machinename,:eventname

	def initialize(stagename,actorname,machinename,longname)
		super()
		from_longname!(longname)
		fill_missing!(stagename,actorname,machinename)
	end	
	
	def from_longname!(longname)
		address=longname.split(".")
		from_array!(address)
	end
	
	def to_longname
		return [@stagename,@actorname,@machinename,@eventname].join(".")
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
	
	def match?(other)
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
# ����� �������, � ������� ���� HFSMComps � �������� �������� (payload)
####################################################################################################
class HFSMEvent < HFSMObject

	attr_reader :from, :to

	def initialize(stagename,actorname, machinename, longname,payload=Hash.new)
		super()
		@payload=payload
		@from=HFSMAddress.new(stagename,actorname,machinename,"")
		@to=HFSMAddress.new(stagename,actorname,machinename,longname)
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
	
	def name
		return @to.to_longname
	end
	
end


class HFSMHandler < HFSMDSL
	@@allowed_elements=[]
	
	def initialize(longname,expr,&block)
		super()
		@longname=longname
		@expr=expr
		@block=block

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
	
	def addressmatch
			HFSMAddress.new(stage.key,actor.key,machine.key,@longname)
	end
	
	def match_context?(context)
		if addressmatch.match?(context.event.to)
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
		if state.key==machine.current_state.key
			context=HFSMContext.new(stage,actor,machine,event)
			if match_context?(context)
				execute(context)
			end
		end
		
	end
	
	
	def execute(context)
		context.instance_eval(&@block)
	end
	
	def setup
		subscribe_to_events(addressmatch)
	end
	
	def subscribe_to_events(address)
		stage.subscribe(address,self)
	end
	
end	



class HFSMState < HFSMDSL
	@@allowed_elements=[HFSMHandler]
	
	def initialize
		super

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
			context=HFSMContext.new(stage,actor,machine,HFSMEvent.new(stage.key,actor.key,machine.key,""))
			context.instance_eval(&@entry)
		end
	end
	
	def leave_state
		if @leave
			context=HFSMContext.new(stage,actor,machine,HFSMEvent.new(stage.key,actor.key,machine.key,""))
			context.instance_eval(&@leave)
		end
	end
	
	def entry(&block)
		self.setEntry(&block)
	end

	def leave(&block)
		self.setLeave(&block)
	end
	
	def on(eventname,expr=nil,&block)
		obj=HFSMHandler.new(eventname,expr,&block)
		self.addElement(eventname,obj)
	end

	def with
		Proc.new
	end
	
end



class HFSMMachine < HFSMDSL
	@@allowed_elements=[HFSMState]
	attr_reader :current_state
	
	def initialize
		super

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
		super
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
			raise HFSMStateException,"HFSM Error: Unknown state %s in machine %s of %s" % [statename,@key,@parent.key]
		end
	end
	
	def state(key, &block)
		obj=HFSMState.new
		self.addElement(key,obj)
		obj.instance_eval(&block)		
	end
	
end


class HFSMActor < HFSMDSL
	@@allowed_elements=[HFSMMachine]
	
	def initialize
		super
		createDefers
	end
	
	def stage
		@parent.stage
	end
	
	def actor
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
# ������, ������������� ������� ��������� � ��������� �� Actor'��
####################################################################################################
class HFSMStage < HFSMDSL
	@@allowed_elements=[HFSMActor]
	
	def initialize(name)
		super()
		@key=name
		@queue=HFSMQueue.new
		@subscribers=[]
		createDefers
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
	
	def subscribe(address,handler)
		puts "Subscribing %s to %s" % [address.to_longname,handler]
		@subscribers << HFSMSubscription.new(address,handler)
	end
	
	def dispatch(event)
		@subscribers.each {|sub| sub.handler.try_handle(event)}
	end
	
	def self.actor(key, supplied=HFSMActor, &block)
		deferred do
			if supplied.class==Class
				obj=supplied.new
			else
				obj=supplied
			end
			self.addElement(key,obj)
			if block
				obj.instance_eval(&block)
			end
			
		end
	end

end

	

####################################################################################################
# ��������, � ������� ����������� ����������� ������� � ����������� ������� 'with'
####################################################################################################
class HFSMContext < HFSMBase
	def initialize(stage,actor,machine,event)
		@stage=stage
		@actor=actor
		@machine=machine
		@event=event
	end
	
	def goto(statename)
		@machine.change_state(statename)
	end
	
	def signal(longname,payload=Hash.new)
		event=HFSMEvent.new(@stage.key,@actor.key,@machine.key,longname,payload)
		@actor.parent.post(event)
	end
	
	def reply(shortname,payload=Hash.new)
		event=HFSMEvent.new(@event.from.stagename,@event.from.actorname,@event.from.machinename,shortname,payload)
		@actor.parent.post(event)
	end
	
	def reset
		@machine.reset
	end
	
	def actor
		@actor.key
	end
	
	def machine
		@machine.key
	end
	
	def event
		@event
	end
end










