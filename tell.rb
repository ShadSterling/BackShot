#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8
#
# !!! enforce line endings LF only !!!
# shell may fail to correctly recognize interpreter if CR precedes or replaces LF
#
#---------#---------#---------#---------#---------#---------#---------#---------#---------#---------#
#++
#
# === tell.rb
# Tell messages to the user, with branched logging
#
# Author::    Shad Sterling <mailto:me@shadsterling.com>
# Version::   0.0.1
# Copyright:: Copyright (c) 2011 Shad Sterling
# License::   AGPL
#
#
# Passes messages up from the current branch to the parent branch, and saves messages to a log file.
#
# Each message is logged to the branch log; unless suppressed it is also output to the user; if
# specified it is also promoted to the parent branch.
#
# Output to the user is only performed in the originally invoked branch.  Each branch has a user
# output object, set at branch creation time, which defaults to that of the parent.
#
# Promotion to the parent branch is specified by a numerical "promotion factor," which defaults to
# zero.  Each branch has a "demotion constant," which defaults to one, and is subtracted from the
# promotion factor after logging the message and before promoting the message.  When the promotion
# factor reaches zero, the message is no longer promoted.  An exception is raised if the promotion
# factor is to large to be modified by subtracting the demotion constant.
#
# Branches have:
# • Name
# • User output
# • Log output
# • Parent
# • Demote constant
# • Track message level
# • Mark default
# • Level default
# • Surpress default
# • Promote default
#
# Messages have:
# • Mark character
# • Message body
# • Level
# • Surpress flag
# • Promote factor
# • File of origin
# • Line in file

require 'fileutils' #for Tell#move

# Tell messages to the user, with branched logging
class Tell

	VERSION = "0.0.1"
	DATEOUT = "%a %Y-%b-%d %H:%M:%S (%Z)" #date formatting string (strftime)
	ENDMAT = " %s - %6s - %s - %s" #log open/close formatting string
	ENDOP = "Session Opened"
	ENDCL = "Session Closed"
	FORMAT = "[%s - %6s - %s - %6s]   %1s   %s" #log entry formatting string
	SOURCE = "  \t @ %s : %d" #log entry source tracking tail
	LADDER = "  \t & %d ➝ %d" #log entry promotion tracking tail
	LEVELS = [ :hose, :debug, :detail, :info, :WARN, :ERROR, :FATAL ]
	RANGE = (0...LEVELS.length)
	FATAL = LEVELS.index(:FATAL)
	ERROR = LEVELS.index(:ERROR)
	WARN = LEVELS.index(:WARN)
	INFO = LEVELS.index(:info)
	DETAIL = LEVELS.index(:detail)
	DEBUG = LEVELS.index(:debug)
	HOSE = LEVELS.index(:hose)

	class << self
		alias :_new :new 	#hiding some initializer options from public

		# Create a new parentless branch using a writable IO object and passing all levels
		def new( args )
			#puts "Tell.new "+args.inspect
			bad = args.keys-[ :name, :user, :log, :demote, :track, :mark, :level, :surpress, :promote ]
			raise ArgumentError.new( "Unknown arguments: "+bad.map{|k| k.inspect+" => "+args[k].inspect }.join(", ") ) unless 0==bad.length
			b = _new( args )
			if block_given?
				r = yield( b )
				b.close
			else
				r = b
			end
			r
		end
	end

	# Create a new branch
	def initialize( args )
		#puts "Tell.initialize "+args.inspect
		bad = args.keys-[ :name, :user, :log, :parent, :demote, :track, :mark, :level, :surpress, :promote ]
		raise ArgumentError.new( "Unknown arguments: "+bad.map{|k| k.inspect+" => "+args[k].inspect }.join(", ") ) unless 0==bad.length
		@name = args[:name]; raise ArgumentError.new( "branch name must be specified" ) if nil==@name
		@user = args[:user]; raise ArgumentError.new( "user output destination must be specified" ) if nil==@user
		@log = args[:log]; raise ArgumentError.new( "log output destination must be specified" ) if nil==@log
		@parent = args[:parent]
		@demote = args[:demote] || 1; raise ArgumentError.new( "demotion constant must be nonnegative" ) if 0>@demote
		@track = args[:track] || DETAIL
		@mark = args[:mark] || "0"
		@level = args[:level] || INFO; raise ArgumentError.new( "message level #{@level} is out of range (#{RANGE})" ) unless RANGE.include?(@level)
		@surpress = args[:surpress] || false
		@promote = args[:promote] || 0; raise ArgumentError.new( "default promotion count must be nonnegative" ) if 0>@promote
		parts = [ Time.now.strftime(DATEOUT), $$, fullname(), ENDOP, ]
		output = "\n"+ENDMAT % parts
		begin
			@logpath = nil
			@log.puts( output )
		rescue NoMethodError #probably because @log is a string
			@logpath = @log.to_s
			@log = File.open( @logpath, "ab" )
			@log.sync = true
			@log.puts( output )
		end
		@log.flush
	end

	# Get chain of parent branch names
	def fullname; ( nil==@parent ? "" : @parent.fullname()+" : " ) + @name; end
	
	def name; @name; end

	# Create a child branch
	def branch( args )
		#puts "Tell.branch "+args.inspect
		bad = args.keys-[ :name, :user, :log, :demote, :track, :mark, :level, :surpress, :promote ]
		raise ArgumentError.new( "Unknown arguments: "+bad.map{|k| k.inspect+" => "+args[k].inspect }.join(", ") ) unless 0==bad.length
		args[:user] = args[:user] || @user
		args[:parent] = self
		args[:demote] = args[:demote] || @demote
		args[:mark] = args[:mark] || @mark.succ
		args[:level] = args[:level] || @level
		args[:surpress] = args[:surpress] || @surpress
		args[:promote] = args[:promote] || @promote
		b = self.class._new( args )
		if block_given?
			r = yield( b )
			b.close
		else
			r = b
		end
		r
	end

	# Log a message
	def tell( args )
		#puts "Tell#tell "+args.inspect
		bad = args.keys-[ :mark, :message, :level, :surpress, :promote, :file, :line ]
		raise ArgumentError.new( "Unknown arguments: "+bad.map{|k| k+" => "+args[k] }.join(", ") ) unless 0==bad.length
		mark = (args[:mark] || @mark)[0..0]
		message = args[:message]; raise ArgumentError.new( "message to tell must be specified" ) if nil==message
		level = args[:level] || @level; raise ArgumentError.new( "message level #{level} is out of range (#{RANGE})" ) unless RANGE.include?(level)
		surpress = args[:surpress]; surpress = @surpress if nil==surpress
		promote = args[:promote] || @promote
		file = args[:file]; raise ArgumentError.new( "source file must be specified" ) if nil==file
		line = args[:line]; raise ArgumentError.new( "line in source file must be specified" ) if nil==line
		parts = [ Time.now.strftime(DATEOUT), $$, fullname(), LEVELS[level], mark, message ]
		format = FORMAT
		track = level<=@track
		if track then
			format += SOURCE
			parts += [ file, line ]
		end
		output = parent = format % parts
		demote = promote - @demote
		output += LADDER % [promote, demote] if track
		@log.puts( output ); @log.flush
		unless surpress then
			@user.puts( output ); @user.flush
		end
		@parent.inject( demote, parent, track ) if demote >= 0
		output
	end

	def inject( promote, parent, track )
		#puts "Tell#inject "+args.inspect
		output = parent
		demote = promote - @demote
		output += LADDER % [promote, demote] if track
		@log.puts( output ); @log.flush
		@parent.inject( demote, parent, track ) if promote > 0
	end

	#move logfile (new messages go to new file)
	#when this fails, it will close the existing log before raising an exception
	#when it succeeds it will return the previous log file name
	def move( newname )
		raise "cannot move logfile: originally recieved output object, not filename" if nil==@logpath
		@log.close
		newpath = newname.to_s
		FileUtils.mv( @logpath, newpath)
		oldpath = @logpath
		@logpath = newpath
		@log = File.open( newpath, "ab" )
		oldpath
	end

	#end branch session
	def close
		#puts "Tell#close "+args.inspect
		parts = [ Time.now.strftime(DATEOUT), $$, fullname(), ENDCL, ]
		output = ENDMAT % parts+"\n\n"
		@log.puts( output ); @log.flush
		@log.close if nil!=@logpath
		#@user.close   #NO! don't close stdout!
	end

	def closed?; @log.closed?; end

end

#provides a default tell object
module Teller
	@@file=nil
	@@teller=nil
	def logfile; @@file; end
	def teller; @@teller; end
	def name; @@teller.name; end
	def init; if nil==@@teller or @@teller.closed?
		name = File.basename($0)
		@@file = name+".log"
		@@teller = Tell.new( :name => name, :user => $stdout, :log => @@file )
	end; end
	def tell( args ); init; @@teller.tell( args ); end
	def branch( args )
		init
		if block_given? then
			@@teller.branch( args ) { |a| yield a }
		else
			@@teller.branch( args )
		end
	end
	def close; @@teller.close unless nil==@teller or @@teller.closed; end
	def closed?; nil!=@@teller && @@teller.closed; end
end


if $0 == __FILE__
	include Teller
	teller.close
	tell( :message => "Tell version "+Tell::VERSION, :file => __FILE__, :line => __LINE__ )
	branch :name => "branch", :log => name+".branch.log" do |b|
		b.tell( :message => "Branch test", :file => __FILE__, :line => __LINE__ )
		tell( :message => teller.inspect, :file => __FILE__, :line => __LINE__ )
		b.tell( :message => b.inspect, :file => __FILE__, :line => __LINE__ )
	end
	teller.close
	tell( :message => "Tell version "+Tell::VERSION, :file => __FILE__, :line => __LINE__ )
end
