#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8

# === backshot/library.rb
# Helper library for BackShot
#
# Author::    Shad Sterling <mailto:me@shadsterling.com>
# Copyright:: Copyright (c) 2005-2018 Shad Sterling
# License::   AGPL

class BackupSet
	attr_accessor :dirs, :totalsize, :files, :relinked, :saved, :sockets, :fifos, :newsize
	attr_reader :name, :tag, :target, :entries, :exclude, :method, :arguments, :source, :path
	#local path of source, either native local path or mount point of remote source
	def from; [nil,""].include?( @mountpoint ) ? @source : File.join( @mountpoint, @path); end
	MOUNTERS = {
		#:cmd => actual binary to use
		#:rename => transforms mount target in the same way as the mount command, to match what's returned by mount after this mount succedes
		"cifs" => { :cmd => "/sbin/mount.cifs" },
		"smb" => { :cmd => "/usr/bin/smbmount", :rename => Proc.new {|name| name.gsub(" ","_") } },
	}
	MOUNTERS["mount.cifs"] = MOUNTERS["cifs"]
	MOUNTERS["/sbin/mount.cifs"] = MOUNTERS["cifs"]
	MOUNTERS["smbmount"] = MOUNTERS["smb"]
	MOUNTERS["/usr/bin/smbmount"] = MOUNTERS["smb"]
	def mountwith; MOUNTERS[@mountcommand]; end
	def initialize( *parts )
		@method = nil
		@arguments = ""
		@exclude = []
		@relinked = 0
		@saved = 0
		@newsize = 0
		@totalsize = 0
		@entries = 0
		@files = 0
		@dirs = 0
		@sockets = 0
		@fifos = 0
		@mounted = false
		@makemount = true
		@mountcommand = nil
		@mountpoint = nil
		@mountoptions = nil
		@fallback = nil
		parts.each do |part|
			case part[0]
				when :name
					@name = part[1]
				when :tag
					@tag = part[1]
				when :source
					@source = part[1]
					@source += File::SEPARATOR unless File::SEPARATOR == @source[-1..-1] # ensure trailing slash for consistency
					parts = @source.split(File::SEPARATOR) #does not have trailing empty string; loses trailing separator!
					#puts @source.inspect
					#puts "#{parts.length}: #{parts.inspect}"
					if parts.length > 3 then
						@mount = parts[0..3].join(File::SEPARATOR)+File::SEPARATOR #add trailing separator to mount point
						@path = parts[4..-1].join(File::SEPARATOR)+File::SEPARATOR #add trailing separator to path
					else
						@mount = @source
						@path = ""
					end
					#puts "#{@mount.inspect} + #{@path.inspect}"
				when :fallback
					@fallback = part[1]
				when :mountpoint
					@mountpoint = part[1]
					@mountpoint += File::SEPARATOR unless File::SEPARATOR == @mountpoint[-1..-1] # add trailing slash for consistency - note that this requires mount detection exception
					@makemount = false
				when :mountcommand
					@mountcommand = part[1]
				when :mountoptions
					@mountoptions = part[1]
				when :target
					@target = part[1]
					@target += File::SEPARATOR unless File::SEPARATOR == @target[-1..-1] # add trailing slash so that rsync will work - note that this requires exception in call to coiterate for consistency
				when :exclude
					@exclude.concat part[1]
				when :method
					raise ArgumentError, "unknown method #{part[1].inspect}" unless [:rsync,:scp].include?(part[1])
					@method = part[1]
				when :arguments
					 @arguments += " "+part[1]
				else
					raise ArgumentError, "unknown key #{part[0].inspect} (set to #{part[1].inspect})"
			end
		end
		MOUNTERS[@mountcommand] = { :cmd => @mountcommand } if nil == mountwith
		if nil == @method then
			if [nil,""].include?( @source) then
				@method = :archive
			else
				@method = :rsync
			end
		end
	end
	# tests weather anything is mounted on @mountpoint
	# returns one of :nop, :source, :fallback, :other, :none
	def mounted?
		if( [nil,""].include?( @mountcommand ) ) # no mount command; assuming no mounting to do
			:nop
		elsif @makemount and [nil,""].include?( @mountpoint )
			:none
		else
			test=mountstring
			if( "" != test ) # something is mounted there
				netpath = File::SEPARATOR != @mount[-1..-1] ? @mount : @mount[0...-1] #remove trailing separator
				netpath = mountwith[:rename].call(netpath) if mountwith[:rename] #smbmount doesn't report the same name as was actually mounted
				if( test.include?( netpath ) ) # source is mounted
					:source
				elsif( @fallback and test.include?( @fallback ) ) # fallback is mounted
					:fallback
				else # something else is mounted
					:other
				end
			else # nothing is mounted there
				##TODO: clear point if @makemount == true
				:none
			end
		end
	end
	#returns the string indicating what's mounted on @mountpoint
	def mountstring
		unless [nil,""].include?( @mountpoint )
			mountpoint = File::SEPARATOR != @mountpoint[-1..-1] ? @mountpoint : @mountpoint[0...-1]
			r = "mount | grep \"#{mountpoint}\""
			r = `#{r}`
			r
		else
			""
		end
	end
	# attempts to mount the source for this set
	# returns an array [:status, "message", "command", "result"]
	# where :status is one of :nop, :success, :failure, :fallback, :abort
	def mount( fallback = false )
		#puts "mount()"
		message = ""
		command = nil
		result = nil
		#puts @source
		#puts mountwith[:rename].call(@source) if mountwith[:rename] #smbmount doesn't report the same name as was actually mounted
		if( [nil,""].include?( @mountcommand ) )
			status=:nop; message = "no mount comand given; assuming no mount is necessary"
		elsif( @makemount == false and [nil,""].include?( @mountpoint ) )
			status=:abort; message = "no mount point given"
		elsif( [nil,""].include?( @mountoptions ) )
			status=:abort; message = "mount options are required"
		else
			if @makemount then
				#create mount point within $mountroot
				#puts " ---- new style mount ----"
				mountpoint = File.join( $mountroot, "temp-pid_#{Process.pid}--#{sprintf("%X", Thread.current.object_id)}-#{100000+rand(900000)}" )
				#puts " @ #{mountpoint}"
				Dir.mkdir mountpoint
				@mountpoint = mountpoint
				#puts " made, mounting"
			end
			m = mounted?
			#puts m.inspect
			case m
				when :source
					status=:success; message = "already mounted"
				when :fallback
					status=:fallback; message = "fallback already mounted"
				when :other
					status=:abort; message = "mount point already in use: #{mountstring}"
				when :none
					mounter = mountwith[:cmd]
					netpath = File::SEPARATOR != @mount[-1..-1] ? @mount : @mount[0...-1] #remove trailing separator
					command="#{mounter.cmdsafe} #{netpath.cmdsafe} #{@mountpoint.cmdsafe} -o #{@mountoptions.cmdsafe}"
					#puts command
					result = `sudo #{command} 2>&1`
					#puts result
					m = mounted?
					#puts m.inspect
					case m
						when :source
							status=:success; message = "mount successful"
							@mounted = true
						when :fallback
							status=:fallback; message = "magical fallback from mount"
							@mounted = true
						when :other
							status=:abort; message = "magical change from mount"
							@mounted = true
						when :none
							if fallback then # fallback is enabled
								if( ! [nil,""].include?( @fallback ) ) # there is a fallback
									command = "sudo mount --bind #{@fallback.cmdsafe} #{@mountpoint.cmdsafe}"
									result = `sudo #{command} 2>&1`
									case mounted?
										when :source
											status=:success; message = "mount failed, magical fallup from fallback bind"
										when :fallback
											status=:fallback; message = "mount failed, binding to fallback successful"
										when :other
											status=:abort; message = "mount failed, magical change from fallback bind"
										when :none
											status=:failure; message = "mount failed, binding to fallback failed"
										else
											status=:abort; message = "invalid return value from #{self.class}#mounted?"
									end
								else # there is no fallback
									status=:failure; message = "mount failed, no fallback"
								end
							else # fallback is disabled
								status=:failure; message = "mount failed, fallback disabled"
							end
						else
							status=:abort; message = "invalid return value from #{self.class}#mounted?"
					end
				else
					status=:abort; message = "invalid return value from #{self.class}#mounted?"
			end
			if @makemount then
				# mount point must be unset on failure
				#puts " confirming"
				case status
					# status is one of :nop, :success, :failure, :fallback, :abort
					when :nop, :failure, :abort
						#puts " failed, removing"
						mountpoint = @mountpoint
						@mountpoint = nil
						Dir.rmdir mountpoint
					when :success, :fallback
						#puts " mounted, retaining"
					else
						raise "illegal mount status at temporary mount point confirmation: #{status.inspect}"
				end
				#puts " ---- end new style mount ----"
			end
		end
		[status,message,command,result]
	end
	def unmount
		if @mounted then
			#puts "unmounting #{@mountpoint}"
			c = "umount #{@mountpoint.cmdsafe} 2>&1"
			#puts c
			r = `#{c}`
			#puts r
			fail = "" == r ? false : true
			if fail then
				#puts "failure"
				false
			else
				#puts "success"
				if @makemount then
					#puts " ---- new style unmount ----"
					#puts " removing unmounted point"
					mountpoint = @mountpoint
					@mountpoint = nil
					Dir.rmdir mountpoint
					#puts " ---- end new style unmount ----"
				end
				true
			end
		else
			true
		end
	end
	def to_h
		r = { :name => @name.sdup, :source => @source.sdup }
		r[:fallback] = @fallback.sdup unless nil == @fallback
		r[:mountpoint] = @mountpoint.sdup unless nil == @mountpoint
		r[:mountcommand] = @mountcommand.sdup unless nil == @mountcommand
		r[:mountoptions] = @mountoptions.sdup unless nil == @mountoptions
		r[:target] = @target.sdup
		r[:exclude] = @exclude.sdup unless nil == @exclude
		r[:method] = @method.sdup
		r[:arguments] = @arguments.sdup unless nil == @arguments
		r
	end
end

#go through directories in sets, recursivly calling block on each entry in any set
#used to consider pathes of the form root/base/top
#peramiters:
#- root <= the root path which everything else is within
#- top <= the top path which is the same for all bases
#- *list <= list of base paths within the root path
#- block <= the block to do something with each entry
#peramiters passed to the block:
#- message <= an informational message that may be useful relating status to a user
#- root <= the same root given to this function
#- top <= the same top giiven to this function
#- name <= an entry in at least one root/base/top
#- *newlist <= list of base pathes with stat objects for each; list[n][1] = lstat(root/list[n][0]/top/name)
#if the block returns true, the name it was called with is added to the recursion list; after all calls to block this function will call itself for each name for which block returned true.
def coiterate( root, top, *list, &block )
	dirhash = {} #quick-access list of entries
	names = [] #sequential list of entries to pass to block
	recurse = [] #list of names to recurse into
	#generate list of all entries in each version:
	# dirhash[name] => name; this is just to faster than array#include?; names should just be an orderedhash
	# names[n] => name; for each n, there is an m where root/list[m]/top/name exists
	list.each_with_index do |base,index| #iterate over base pathes
		fullbase=File.join(root,base,top)
		Dir.foreach(fullbase) do |name| #iterate over entries in this base path
			next if [".",".."].include?(name)
			a = dirhash[name]
			if nil == a then
				a = name
				names << a
				dirhash[name] = a
			end
		end if File.directory?(fullbase)
	end
	#sort names (makes watching open files - e.g. with $(lsof) - useful for tracking progress)
	names.sort!
	#for each name, generate newlist and call block
	names.each do |name| #iterate over names
		newlist = []
		#generate list of [base, stat] pairs for each entry in any base in list
		# newlist[n] => [base,stat]; for each n, stat = lstat(root/base/top/name)
		list.each do |base| #iterate over base pathes for this name
			fullbase=File.join(root,base,top)
			fullname = File.join(fullbase,name)
			stat = File.lstat(fullname) if File.exist?(fullname)
			newlist << [base,stat]
		end
		#puts "#{Time.now.to_i}\t#{newlist.length} of #{top} / #{name}\"" #DEBUG
		#generate message to dump on error
		message = "#{name}"
		newlist.each do |base,stat|
			message += "\n\t#{base} :\t#{stat.inspect}"
		end
		#call the block; generate recursion entry if block returns true
		if block.call( message, root, top, name, *newlist ) then
			recurse << name
			#puts "!!!!!! #{name}"
		end
	end
	#recurse...
	recurse.each do |name|
		coiterate( root, File.join(top,name), *list, &block )
	end
end

#relink a file, removing a link to a redundant inode and redirecting it to a unique inode
def relink( teller, base, root, top, name, stat, kfull, full = File.join(base,root,top,name) )
	#return false
	begin
		step=:temp; if $prefix == name[0..($prefix.length-1)] then
			raise "Name Collision! temp prefix = \"#{$prefix.length}\""
		else
			vfull = File.join(base,root,top,$prefix+name) #temp name
		end
		step=:link; File.link( kfull, vfull )                      #link temp name to original inode
		if stat.symlink? then
			#puts " .. relinking symlink #{kfull} <- #{vfull} <= #{full}"
			begin
				step=:mode; File.lchmod( stat.mode, vfull )		#set mode on new link
			rescue Exception => e
				teller.tell( :mark => ".", :message => "unable to set mode on new symlink (ok on symlinks): #{e.message}", :file => __FILE__, :line => __LINE__ )
			end
			begin
				step=:user; File.lchown( stat.uid, stat.gid, vfull )	#set owner on new link
			rescue Exception => e
				teller.tell( :mark => ".", :message => "unable to set owner on new symlink (ok on symlinks): #{e.message}", :file => __FILE__, :line => __LINE__ )
			end
			#puts " ..  link mode & owner changed"
		else
			begin
				step=:mode; File.chmod( stat.mode, vfull )		#set mode on new link
			rescue Exception => e
				teller.tell( :mark => "!", :message => "WARNING: Unable to set mode on new file (data is intact, metadata is corrupt): #{e.message}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			end
			begin
				step=:user; File.chown( stat.uid, stat.gid, vfull )	#set owner on new link
			rescue Exception => e
				teller.tell( :mark => "!", :message => "WARNING: Unable to set owner on new file (data is intact, metadata is corrupt): #{e.message}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			end
		end
		#not changing time because times appears to go by inode & I'd rather keep the older set
		step=:clear; FileUtils.rm( full )		#remove link to redundant inode
		step=:move; FileUtils.mv( vfull, full )	#move temp name to real name
		step=:done; true
	rescue Exception => e
		info = { :temp => "before touching filesystem",
		         :link => "creating new inode link with temporary name",
		         :mode => "setting permissions on new link",
		         :user => "setting ownership of new link",
		         :clear => "removing redundant inode link",
		         :move => "moving new link to real name",
		         :done => "after completing relink" }
		info = info[step]
		info = "!! BUG IN RELINK !!" if nil == info
		teller.tell( :mark => "!", :message => "! ERROR ! Relink Failure at step #{step} (#{info})!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
		clean = false
		case step
			when :mode,:user,:clear  #new link was created, old link was not removed; try to remove new link
				clean = true
			when :move  #new link was created, old link was removed, new link was not renamed
				teller.tell( :mark => " ", :message => "! new link is named #{$prefix+name}; #{vfull}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				teller.tell( :mark => " ", :message => "  to recover, rename to \"#{name}\"; ${full}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
		end
		teller.tell( :mark => " ", :message => "        context: #{base} + #{root} + #{top} + #{name}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "           type: #{stat.ftype}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "      redundant: #{full}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "           temp: #{vfull}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "       original: #{kfull}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "failure on step: #{step}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "exception class: #{e.class}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "        message: #{e.message}", :file => __FILE__, :line => __LINE__ )
		teller.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
		if clean then
			begin
				FileUtils.rm( vfull )		#remove temp name
			rescue Exception => f
				teller.tell( :mark => "!", :message => "! ERROR ! Failed to remove new link (with temp name) while recovering!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				teller.tell( :mark => " ", :message => "! new link is named #{$prefix+name}; #{vfull}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				teller.tell( :mark => " ", :message => "  to recover, remove \"#{name}\", and rename \"#{$prefix+name}\" to the same name", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				teller.tell( :mark => " ", :message => "        message: #{f.message}", :file => __FILE__, :line => __LINE__ )
				teller.tell( :mark => " ", :message => "      backtrace: ...\n\t"+f.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
			end
		end
		false
	end
end



class Sample
        def initialize(*names)
                @cols = names.map do |n| n.sdup; end
		@cols.unshift nil
                @samples=[]
                @sizes=[]
		@low=["(low)"]; @high=["(high)"]; @sum=["(sum)"]; @mean=["(mean)"]
        end
	#the first value is special, it's the sample name
	def <<(*values)
		values = values[0] if 1 == values.length
		s=[]
		@samples << s
		values.each_with_index do |v,i|
			s[i]=v.to_s
			@sizes[i] = s[i].length if nil == @sizes[i] or @sizes[i] < s[i].length
			next if 0 == i or not Numeric === v
			@low[i] = v if nil == @low[i] or @low[i] > v
			@high[i] = v if nil == @high[i] or @high[i] < v
			@sum[i] = nil==@sum[i] ? v : @sum[i]+v
			@mean[i] = @sum[i] / @samples.length
		end
		#puts s.inspect
	end
	def report(tail=true)
		r = @samples.sdup
		if tail then
			r << nil
			[@low,@high,@sum,@mean].each do |s|
				q = []
				s.each_with_index do |v,i|
					v = v.to_s
					@sizes[i] = v.length if @sizes[i] < v.length
					q << v
				end
				r << q
			end
		end
		s = ""
		r.each_with_index do |m,j|
			if nil == m then
				s << "\n"
				next
			end
			a = []
			m.each_with_index do |v,i|
				v = v.rjust(@sizes[i])
				if 0 == i  then
					a << v+": "
				elsif nil != @cols[i]
					a << @cols[i]+": "+v
				else
					a << v
				end
			end
			#puts a.inspect
			s << a.join("  ")+"\n"
		end
		#puts ": [#{@low.join(", ")}]"
		#puts ": [#{@high.join(", ")}]"
		#puts ": [#{@sum.join(", ")}]"
		#puts ": [#{@mean.join(", ")}]"
		s
	end
	def get(what,col)
		#puts "getting #{what} for #{col}"
		col = @cols.index(col)
		#puts "column: #{col}"
		what = [[:low,@low],[:high,@high],[:sum,@sum],[:mean,@mean]].assoc(what)[1]
		#puts "of: [#{what.join(", ")}]"
		r = what[col]
		#puts " => #{r.inspect}"
		r
	end
	def low(col); get(:low,col); end
	def high(col); get(:high,col); end
	def sum(col); get(:sum,col); end
	def mean(col); get(:mean,col); end
end
