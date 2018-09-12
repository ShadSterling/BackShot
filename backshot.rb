#!/usr/bin/env ruby
# encoding: UTF-8
$VERBOSE = true

# !!! enforce line endings LF only !!!
# shell may fail to correctly recognize interpreter if CR precedes or replaces LF
#---------#---------#---------#---------#---------#---------#---------#---------#---------#---------#

#++
#
# === backshot.rb
# Snapshot-style cross-linking directory tree backups
#
# Author::    Shad Sterling <mailto:me@shadsterling.com>
# Version::   0.0.4
# Copyright:: Copyright (c) 2005-2018 Shad Sterling
# License::   AGPL


require 'date'; startat=Time.now
require 'fileutils'
require 'pathname' #used for finding relative paths
require 'yaml' #used for timeinfo

$:.unshift(File.dirname(__FILE__)) #look for my libraries in the same dir as this file
require 'ext' #My extensions to standard classes
require 'library' #BackShot class definitions
require 'lock' #handles lock files
require 'show' #variation on prettyprint
require 'tell' #inform the user

_backshot_version = "0.0.4"
_time_format = "%a %Y-%b-%d %H:%M:%S.%N (%Z)"  #used for strings in timeinfo
_name_format = "%Y-%m%b-%d%a.%H-%M-%S.%Z" #used for snapshot names

#This will become a real config file eventually
config = eval( IO.read(File.join( File.dirname(__FILE__), 'config.rb') ), binding, "config.rb")
$mountroot = config[:mountroot]  #used for sets with no specified mountpoint; creates "#{$mountroot}/#{foo}"
$prefix = config[:prefix]        #for temp files
$dateout = config[:dateout]
root = config[:root]             #directory containing snapshots
lockfile = File.join( root, "lock.backshot" )
verbose = config[:verbose]
backupsets = config[:backupsets]
backupintervals = config[:backupintervals]
$superuser = config[:superuser]; $superuser=(0==Process.euid) unless [true,false].include?($superuser)
newversion = startat.strftime(_name_format)

timeinfo={:snapshot=>{:name=>newversion,:start_unix=>startat.to_i,:start_string=>startat.strftime(_time_format)},:pedigree=>{:source=>"original run",:generator=>"BackShot",:version=>_backshot_version},:sets=>{}}

#backupsets = backupsets[0..0]

$stdout.sync
$stderr.sync
STDOUT.sync
STDERR.sync

logfile = File.join( root, newversion+".log" )
w = Tell.new( :name => "backshot", :log => logfile, :user => STDOUT )

w.tell( :mark => "*", :message => "* * BackShot "+_backshot_version, :file => __FILE__, :line => __LINE__ )
w.tell( :mark => "!", :message => "WARNING: ignoring obsolete config option :lockfile => #{config[:lockfile]}", :file => __FILE__, :line => __LINE__ ) unless nil == config[:lockfile]
w.tell( :mark => "*", :message => "adding snapshot to #{root}", :file => __FILE__, :line => __LINE__ )
w.tell( :mark => "+", :message => "superuser mode is "+($superuser?"ENABLED":"NOT enabled"), :file => __FILE__, :line => __LINE__ ) if verbose

lock = file_lock( lockfile )
if :created != lock[0] then
	w.tell( :mark => "!", :message => "! FATAL ERROR ! Failed to create lock!", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "  Lockfile status: #{lock.show}", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "!! Aborting !!", :file => __FILE__, :line => __LINE__ )
	exit
end

versions = [] #version list
info = {} #information about each version

#get stat objects for each version root
unless File.directory?(root) then
	if File.exists?(root) then
		w.tell( :mark => "!", :message => "! FATAL ERROR ! Snapshot root is not a directory!", :file => __FILE__, :line => __LINE__ )
		w.tell( :mark => " ", :message => "  snapshot root: #{root}", :file => __FILE__, :line => __LINE__ )
		w.tell( :mark => " ", :message => "           type: #{File.ftype(root)}", :file => __FILE__, :line => __LINE__ )
	else
		w.tell( :mark => "!", :message => "! FATAL ERROR ! Snapshot root does not exist!", :file => __FILE__, :line => __LINE__ )
		w.tell( :mark => " ", :message => "  snapshot root: #{root}", :file => __FILE__, :line => __LINE__ )
	end
		w.tell( :mark => " ", :message => "!! Aborting !!", :file => __FILE__, :line => __LINE__ )
	exit
else
	Dir.foreach(root) do |name|
		begin
			next if [".",".."].include?(name) #r rand > 0.15
			fullname = File.join(root,name)
			s = File.lstat(fullname)
			next unless s.directory?
			t = ti = tn = nil #ensure scope
			begin
				tn = File.join( fullname, "timeinfo" )
				ti = YAML.load_file( tn )
				t = Time.at(ti[:snapshot][:start_unix])
				th = {:snapshot=>ti[:snapshot],:pedegree=>ti[:pedigree]}
				#w.tell( :mark => ".", :message => "loaded timeinfo record for #{name}, start time was #{t}...\n\t#{th.inspect}", :file => __FILE__, :line => __LINE__ )
			rescue Errno::ENOENT, NoMethodError => e #missing or corrupt timeinfo
				w.tell( :mark => "!", :message => "missing or corrupt timeinfo record for #{name}, falling back on .starttime.", :file => __FILE__, :line => __LINE__, :surpress => true ) if verbose
				ti={:snapshot=>{:name=>name.sdup},:pedigree=>{:generator=>"BackShot",:version=>_backshot_version}}
				begin
					t = File.open( File.join( fullname, ".starttime" ), "rb" ) { |f| Marshal.load( f ) }
					ti[:pedigree][:source] = "converted from .starttime"
					ti[:snapshot][:start_unix] = t.to_i; ti[:snapshot][:start_string] = t.strftime(_time_format)
					#w.tell( :mark => ".", :message => "loaded starttime record for #{name}, start time was #{t}", :file => __FILE__, :line => __LINE__ )
				rescue Errno::ENOENT => e #missing .starttime
					w.tell( :mark => "!", :message => "missing .starttime record for #{name}, attempting to regenerate.", :file => __FILE__, :line => __LINE__ )
					t = Time::strptime_local( name, _name_format )
					v = t.strftime(_name_format)
					ti[:pedigree][:source] = "recovered from snapshot name"
					unless v === name
						t = Time::strptime_local_dst( name, _name_format )
						v = t.strftime(_name_format)
						ti[:pedigree][:source] = "recovered from snapshot name (adjusted for DST)"
					end
					unless v === name
						#t = s.mtime
						c = nil
						Dir.foreach(fullname) do |child|
							u = File.lstat(File.join(fullname,child)).mtime
							if u < t
								t = u
								c = child
							end
						end
						v = t.strftime(_name_format)
						ti[:pedigree][:source] = "recovered from mtime of subdirectory \"#{c}\"" unless nil == c
					end
					if v === name
						w.tell( :mark => ".", :message => "regenerating missing starttime record for #{name}", :file => __FILE__, :line => __LINE__ )
						File.open( File.join( fullname, ".starttime" ), "wb" ) { |f| Marshal.dump( t, f ) }
					else
						w.tell( :mark => "!", :message => "not regnerating missing starttime record for #{name}: mismatch with generated string #{v}", :file => __FILE__, :line => __LINE__ )
						ti[:pedigree][:source] += " - mismatch with snapshot name"
					end
				end
				ti[:snapshot][:start_unix] = t.to_i; ti[:snapshot][:start_string] = t.strftime(_time_format)
				w.tell( :mark => ".", :message => "regenerated missing timeinfo for #{name}; #{ti[:pedigree][:source]}", :file => __FILE__, :line => __LINE__ )
				w.tell( :mark => ".", :message => "regenerated timeinfo:  #{ti.inspect}", :surpress=>!verbose, :file => __FILE__, :line => __LINE__ )
				File.open( tn, "wb" ) { |f| f.puts ti.to_yaml }
			end
			versions << [name,s,t]
		rescue Exception => e
			w.tell( :mark => "!", :message => "! FATAL ERROR ! Exception while listing previous snapshots!", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "  snapshot root: #{root}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "       snapshot: #{name}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "           path: #{fullname}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "           stat: #{s.inspect}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "      starttime: #{t.inspect}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "       timeinfo: #{ti.inspect}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "      exception: #{e.class} => #{e.message}", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => " ", :message => "!! Aborting !!", :file => __FILE__, :line => __LINE__ )
			exit
		end
	end
end
#versions.sort! { |a,b| a[2] <=> b[2] } #sort by .starttime
versions.sort! { |a,b| b[2] <=> a[2] } #sort by .starttime - newest first
#w.tell( :mark => "-", :message => "#{versions.length} existing versions", :file => __FILE__, :line => __LINE__ )
thinning = config[:thinning]; thinning = 366 if nil == thinning
w.tell( :mark => "-", :message => "#{versions.length} existing versions (considering #{thinning})", :file => __FILE__, :line => __LINE__ )
#puts "#{versions[0][0]} ..#{versions.length}.. #{versions[-1][0]}"
versions = versions.thin_decay(thinning-1) # -1 will be recovered by new snapshot
#puts "#{versions[0][0]} ..#{versions.length}.. #{versions[-1][0]}"
w.tell( :mark => "+", :message => "#{backupsets.length} sets to back up", :file => __FILE__, :line => __LINE__ )

#free space command works on Linux;
# to make it work on OS X I installed ports coreutils, and made ~/bin/df call gdf.
free = "df -B 1 #{root.cmdsafe} | tail -n 1 | awk \'/.*\\n*\\s*\\n*\\s*\\n*.*/ { if ( $1 !~ /\\// ) print $3; else print $4 }\'"
free = `#{free}`.to_i
w.tell( :mark => "-", :message => "#{free} bytes available for snapshots", :file => __FILE__, :line => __LINE__ )

if 0 == versions.length then
	w.tell( :mark => "-", :message => "no latest version to link", :file => __FILE__, :line => __LINE__ )
else
	#lastversion = versions[-1][0]
	lastversion = versions[0][0]
	w.tell( :mark => "-", :message => "latest version is #{lastversion}", :file => __FILE__, :line => __LINE__ )
end

#exit

w.tell( :mark => "-", :message => "creating new version #{newversion}", :file => __FILE__, :line => __LINE__ )

begin
	dest = File.join(root,newversion)
	FileUtils.mkdir_p( dest )
	File.open( File.join( dest, ".starttime" ), "wb" ) { |f| Marshal.dump( startat, f ) }
	#versions << [newversion,File.lstat(File.join(root,newversion)),startat]
	versions.unshift [newversion,File.lstat(File.join(root,newversion)),startat]
rescue Exception => e
	w.tell( :mark => "!", :message => "! FATAL ERROR ! Unable to create new version!", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "        version: #{newversion}", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "           path: #{dest}", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "      exception: #{e.class} => #{e.message}", :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
	w.tell( :mark => " ", :message => "!! Aborting !!", :file => __FILE__, :line => __LINE__ )
	exit
end

logfile = File.join( dest, "backshot.log" )
w.move( logfile )

vernames = versions.map { |name,s,t| info[name] = {:files=>0,:dirs=>0,:sockets=>0,:fifos=>0,:new=>0,:total=>0,:relinked=>0,:saved=>0}; name } #remove stats, init info

#if false then
backupsets.each_with_index do |set,setnum|
	startset = Time.now
	set = BackupSet.new(*set)
	ti={:index=>setnum,:start_unix=>startset.to_i,:start_string=>startset.strftime(_time_format)}
	timeinfo[:sets][set.tag]=ti
	ti[:info]=set.to_h
	setlog = File.join( dest, "backshot-#{setnum}-"+set.tag+".log" )
	w.branch( :name => set.tag, :log => setlog, :surpress => true ) do |x|
		x.tell( :mark => "*", :message => "* (#{setnum+1}/#{backupsets.length}) #{set.name}  --  #{startset.strftime("%A %Y-%b-%d %H:%M:%S")}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
		if [nil,""].include?( set.source ) then
			if :archive != set.method
				x.tell( :mark => "!", :message => "! Invalid Set ! SOURCE absent, but METHOD not set to archive!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				ti[:error]={:summary=>"Invalid Set: SOURCE absent, but METHOD not set to archive"}
				next
			else
				x.tell( :mark => "*", :message => "SOURCE: none - set is archival & carries over with no changes", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			end
		else
			x.tell( :mark => "*", :message => "SOURCE: #{set.source}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
		end
		x.tell( :mark => "*", :message => "TARGET: #{set.target}", :file => __FILE__, :line => __LINE__ )
		setdest = File.join(root,newversion,set.target)
		begin
			FileUtils.mkdir_p( setdest )
		rescue Exception => e
			x.tell( :mark => "!", :message => "Unable to make destination!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			x.tell( :mark => " ", :message => "    destination: #{setdest}", :file => __FILE__, :line => __LINE__ )
			x.tell( :mark => " ", :message => "         source: #{set.source}", :file => __FILE__, :line => __LINE__ )
			x.tell( :mark => " ", :message => "      exception: #{e.class} => #{e.message}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			x.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
			ti[:exception]={:summary=>"Unable to make destination",:class=>e.class,:message=>e.message,:destination=>setdest,:source=>src}
			setdest = nil
		end
		unless nil == setdest then
			begin
				si=ti[:steps]=[]
				case set.method
					when :archive
						#prev = false; last = -1
						prev = false; last = 0
						until prev do
							#last -= 1
							last += 1
							lastversion = vernames[last]
							break if nil == lastversion
							src = File.join(root,lastversion,set.target)
							break if nil == src
							prev = true if File.directory?( src ) and Dir.entries( src ).length > 2 #don't go if the directory either doesn't exist or only contains [".",".."]
						end
						if prev then
							steptime=Time.now
							cmd = "cp -Plr --preserve=all #{src.cmdsafe} #{setdest.cmdsafe}/.."
							x.tell( :mark => "-", :message => "copying previous tree from #{lastversion} (#{Dir.entries( src ).length-2} base-level entries)", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
							x.tell( :mark => ">", :message => cmd, :file => __FILE__, :line => __LINE__ ) if verbose
							si << {:action=>"copy previous snapshot",:command=>cmd,:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format)}
							system( cmd ); code = $?.exitstatus
							x.tell( :mark => "<", :message => "command returned #{code}", :file => __FILE__, :line => __LINE__ ) if verbose
							si[-1][:exitstatus]=code
						else
							x.tell( :mark => "-", :message => "no previous tree to copy", :file => __FILE__, :line => __LINE__ )
							si << {:action=>"copy previous snapshot",:error=>"no previous snapshot to copy"}
						end
					when :rsync
						#prev = false; last = -1
						prev = false; last = 0
						until prev do
							#last -= 1
							last += 1
							lastversion = vernames[last]
							break if nil == lastversion
							src = File.join(root,lastversion,set.target)
							break if nil == src
							prev = true if File.directory?( src ) and Dir.entries( src ).length > 2 #don't go if the directory either doesn't exist or only contains [".",".."]
						end
						if prev then
							steptime=Time.now
							cmd = "cp -Plr --preserve=all #{src.cmdsafe} #{setdest.cmdsafe}/.."
							x.tell( :mark => "-", :message => "copying previous tree from #{lastversion} (#{Dir.entries( src ).length-2} base-level entries)", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
							x.tell( :mark => ">", :message => cmd, :file => __FILE__, :line => __LINE__ ) if verbose
							si << {:action=>"copy previous snapshot",:command=>cmd,:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format)}
							system( cmd ); code = $?.exitstatus
							x.tell( :mark => "<", :message => "command returned #{code}", :file => __FILE__, :line => __LINE__ ) if verbose
							si[-1][:exitstatus]=code
						else
							x.tell( :mark => "-", :message => "no previous tree to copy; this will be the first", :file => __FILE__, :line => __LINE__ )
							si << {:action=>"copy previous snapshot",:message=>"no previous snapshot to copy; this will be the first"}
						end
						begin
							steptime=Time.now
							si << {:action=>"mount remote source"}
							mount = set.mount
							si[-1][:message]=mount[1]
							if :nop != mount[0]
								si[-1].merge!( {:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format)} )
								si[-1][:exitstatus]=mount[0]
								si[-1][:message]=mount[1]
								si[-1][:command]=mount[2]
								si[-1][:result]=mount[3]
							end
							case mount[0]
								when :success, :nop
									go = true
								else
									go = false
									x.tell( :mark => "-", :message => "remote source: #{set.source}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
									x.tell( :mark => "!", :message => "! ERROR ! #{mount[0..1].join(", ")}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
									x.tell( :mark => " ", :message => "        command: #{mount[2]}", :file => __FILE__, :line => __LINE__ )
									x.tell( :mark => " ", :message => "         result: #{mount[3].inspect}", :file => __FILE__, :line => __LINE__ )
									si[-1][:error]="mount failed"
								#puts mount.inspect
							end
							if go then
								steptime=Time.now
								### rsync options
								##  -a *				shorthand for -rlptgoD (unless --files-from is given, in which case it's -lptgoD)
								##  -D					shorthand for --devices --specials
								## --delete *			remove from the reciever any file which would be copied from the sender if it doesn't exist on the sender
								## --delete-during		files to be deleted are deleted when they are encountered (contrast with --delete-before and --delete-after)
								## --delete-excluded *	delete from the reciever any file which would be passed over by an exclusion rule (but not files that aren't included)
								## --devices			preserve device files (requires rsync be run as superuser on reciever)
								##  -g					preserve group (requires rsync be run as superuser on reciever)
								##  -H					preserve hard links
								## --link-dest <DIR>	create hardlinks on reciever when copied file is identical to file within <DIR>
								##  -n					"dry run" - do nothing, show what would be done
								## --numeric-ids *		alwase use numbers for ownership (rather than trying names first and using numbers if names fail)
								##  -o					preserve owner (requires rsync be run as superuser on reciever)
								##  -p					preserve permissions
								##  -r					recursive
								##  -l					preserve symlinks
								##  -S					try to handle sparse files efficiently
								## --specials			preserve special files (ie sockets & fifos)
								## --super				receiver attempts super-user activities
								##  -t					preserve mtimes
								##  -v					be verbose
								##  -X					copy xattrs (if supported by sender & reciever filesystems)
								cmd = "rsync -rlHpogDtS --delete-during --delete-excluded #{set.from.cmdsafe} #{setdest.cmdsafe}"
								cmd += " --super" if $superuser
								#cmd += " --exclude #{root.cmdsafe}" #always exclude backup root
								cmd += " --exclude "+Pathname.new(root).relative_path_from(Pathname.new(setdest)).to_s.cmdsafe
								set.exclude.each do |ex|
									cmd += " --exclude #{ex.cmdsafe}"
								end
								#cmd += " --link-dest #{src.cmdsafe}" if prev #redundant
								cmd += set.arguments;
								x.tell( :mark => "-", :message => "updating new copy (rsync)", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
								x.tell( :mark => ">", :message => cmd, :file => __FILE__, :line => __LINE__ ) if verbose
								si << {:action=>"update copy from source",:command=>cmd,:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format)}
								system( cmd ); code = $?.exitstatus
								x.tell( :mark => "<", :message => "command returned #{code}", :file => __FILE__, :line => __LINE__ ) if verbose
								si[-1][:exitstatus]=code
							end
						ensure
							steptime=Time.now
							#puts " # ensure unmount"
							si << {:action=>"unmount remote source"}
							code = set.unmount
							if :nop != mount[0]
								si[-1].merge!( {:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format)} )
								si[-1][:exitstatus]=code
							else
								si[-1][:message] = "no mount performed; unmount is unnecessary"
							end
							#puts " # unmount complete"
						end
					when :scp
						steptime=Time.now
						### scp options
						## -B	no interaction ("batch mode")
						## -C	enable compression
						## -p	preserve times & permissions
						## -q	surpress progress & diagnostic messages
						## -r	recurse into directories & symlinks
						## -v	verbose output
						# scp FOLLOWS symlinks! should be used only as a last resort
						cmd = "scp -BCpqr#{set.arguments} #{set.from.cmdsafe} #{setdest.cmdsafe}"
						x.tell( :mark => "-", :message => "creating new copy (scp)", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
						x.tell( :mark => "!", :message => "WARNING: scp is not recommended because it undectably replaces symlinks with their target", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
						x.tell( :mark => ">", :message => cmd, :file => __FILE__, :line => __LINE__ ) if verbose
						si << {:action=>"update copy from source",:command=>cmd,:start_unix=>steptime.to_i,:start_string=>steptime.strftime(_time_format),:warning=>"scp follows symlinks, snapshot will contain copies rather than links"}
						system( cmd ); code = $?.exitstatus
						x.tell( :mark => "<", :message => "command returned #{code}", :file => __FILE__, :line => __LINE__ ) if verbose
						si[-1][:exitstatus]=code
					when :sftp
						steptime=Time.now
						### sftp options
						## -C	enable compression
						#sftp is mostly for interactive use
						x.tell( :mark => "!", :message => "! ERROR ! #{set.method} method is unimplemented!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
						ti[:error]={:summary=>"Invalid Set: Method #{set.method} is not implemented"}
						#cmd = "sftp -C #{set.source}
						#puts " - creating new copy (sftp)"
						#puts " > #{cmd}" #if verbose
						#system( cmd ); code = $?.exitstatus
					else
						x.tell( :mark => "!", :message => "! Invalid Set ! No such method as #{set.method}!", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
						ti[:error]={:summary=>"Invalid Set: No such method as #{set.method}"}
				end
				#puts " # finished with #{set.method}"
			rescue Exception => e
				x.tell( :mark => "!", :message => "! BUG IN COPY !", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				x.tell( :mark => " ", :message => "      set state: "+set.inspect, :file => __FILE__, :line => __LINE__ )
				x.tell( :mark => " ", :message => "      exception: #{e.class} => #{e.message}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
				x.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
				ti[:exception]={:summary=>"Bug in Copy",:class=>e.class,:message=>e.message,:destination=>setdest,:source=>src}
			end
			#puts " # finished with copy phase"
		end
		#puts " # finished with destination"
		begin
			base = nil #expose for exception handler - dirname of a version
			top = nil #expose for exception handler  - path between version dir and current item
			name = nil #expose for exception handler - filename of current item
			errmsg = nil #expose for exception handler
			stat = nil #expose for exception handler
			x.tell( :mark => "-", :message => "cleaning & counting", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			relinked = 0
			saved = 0
			top = File::SEPARATOR != set.target[-1..-1] ? set.target : set.target[0...-1]
			coiterate( root, top, *vernames ) do |cerrmsg,croot,ctop,cname,*vers|
				errmsg=cerrmsg; root=croot; top=ctop; name=cname #expose to containing scope
				o = "#{root}/ [..#{vers.length}..] /#{top} / #{name}"
				#puts o
				knowns = []
				recurse = false
				if vers[0][0] != newversion # this recursion has excluded the new snapshot! - this should never happen
					x.tell( :mark => "!", :message => "recursed into old snapshots: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ )
				#elsif nil == vers[0][1] # no stat for this item in the new snapsopt
				#	x.tell( :mark => ".", :message => "absent in new snapshot: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ )
				#else
				elsif nil != vers[0][1] # only process if this item is present (has non-nil stat() result) in the new snapshot
					#vers.each do |vbase,vstat|
					vers.reverse_each do |vbase,vstat| # oldest first
						base=vbase; stat=vstat #expose to containing scope
						### TODO: refactor this:  set indicator for :new or :redundant, and process accordingly at end ... ?[:new,:redundant,:dir]
						count = :files
						if nil == stat then #the file doesn't exist in this version
							#puts " ... nil @ #{base} (ignore)"
							count = nil
						elsif stat.directory? #don't compare directories, recurse into them
							#puts " ... dir @ #{base} (recurse)"
							recurse = true
							count = :dirs
						elsif stat.socket? #sockets are ephemeral anyway; exclude them from snapshots
							#puts " ... sock @ #{base} (remove)"
							x.tell( :mark => ".", :message => "dropping socket: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ )
							count = :sockets
							FileUtils.rm( File.join(root,base,top,name) )
						elsif stat.fifo? #fifos are ephemeral anyway; exclude them from snapshots
							#puts " ... fifo @ #{base} (remove)"
							x.tell( :mark => ".", :message => "dropping fifo: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ )
							count = :fifos
							FileUtils.rm( File.join(root,base,top,name) )
						elsif 0 == knowns.length then #this is the first version of this file
							#puts " ... new @ #{base} (keep)"
							knowns << [base,stat,:keep]
							info[base][:new] += stat.size
							set.newsize += stat.size if base == newversion
							info[base][:total] += stat.size
							set.totalsize += stat.size
							#puts " . first symlink: #{base}/#{top}/#{name}" if stat.symlink?
						else #we need to compare to prior versions of this file
							#puts " ... rep @ #{base} (analize)"
							resolved = false #becomes true when this version is redundant
							knowns.reverse_each do |kbase,kstat,kmode,kdata|
								if stat.ino == kstat.ino	#we've resolved this inode before; no need to analize it again
									case kmode
										when :keep #we're keeping links to this inode
											#puts " ... rep @ #{base}\tof #{kbase}"
										when :relink #we're this inode
											#puts " ... rep @ #{base}\tof #{kbase}\tdup #{kdata}"
											kfull = File.join(root,kdata,top,name)
											if relink( x, root, base, top, name, stat, kfull ) then
												relinked += 1; saved += stat.size
												set.relinked += 1; set.saved += stat.size
												info[base][:relinked] += 1; info[base][:saved] += stat.size
												stat = kstat # so the correct size is added to the totals
											end
										else
											raise "bad mode #{kmode.inspect} !!"
									end
									resolved = true #done with this version
								elsif stat.ftype != kstat.ftype #different type; it's not a duplicate of this one; check next known
									#puts " . symlink: #{root}/ #{base} /#{top} / #{name}" if stat.symlink?
								elsif stat.size != kstat.size #different size; it's not a duplicate of this one; check next known
									#nothing to do
								else #files are same name, type, and size; it's time to compare them
									full = File.join(root,base,top,name)
									kfull = File.join(root,kbase,top,name)
									if stat.file? then #regular file; compare the content
										cmd = "diff -q #{full.cmdsafe} #{kfull.cmdsafe} 2>&1" #cmdsafe means don't use quotes
										diff = `#{cmd}`
										if "" == diff then #data is identical; replace this inode
											resolved=true
										#else
											#data is different; it's not a duplicate of this one; continue
										end
									elsif stat.symlink? then #symbolic link; compare the target
										flink = File.readlink(full)
										kflink = File.readlink(kfull)
										if flink == kflink then #target is identical; replace this inode
											resolved=true
										#else
											#data is different; it's not a duplicate of this one; check next known
										end
										raise "!! #{o}: symlink size misrecorded: #{flink.bytesize} != #{stat.size} (->#{flink.inspect})" unless stat.size == flink.bytesize
										#? count=:symlinks  ##for now, symlinks count as files
									else #unknown type; panic
										raise "!! #{o}: unsupported file type #{stat.ftype}"
									end
									if resolved then  #it's redundant; add to knowns and relink file to older inode
										knowns << [base,stat,:relink,kbase]
										if verbose then
											x.tell( :mark => ".", :message => "relinking #{stat.ftype}: #{o}", :file => __FILE__, :line => __LINE__ )
											x.tell( :mark => " ", :message => "     redundant: #{full}", :file => __FILE__, :line => __LINE__ )
											x.tell( :mark => " ", :message => "      original: #{kfull}", :file => __FILE__, :line => __LINE__ )
										end
										if relink( x, root, base, top, name, stat, kfull, full ) then
											relinked += 1; saved += stat.size
											set.relinked += 1; set.saved += stat.size
											info[base][:relinked] += 1; info[base][:saved] += stat.size
											stat = kstat # so the correct size is added to the totals
										end
									end
								end
								if resolved then #if we've found a previous version of this file which is identical to this version, stop looking.
									break
								end
							end
							unless resolved then #all previously considered versions of this file are not identical to this file
								#puts " ... add @ #{base}"
								#x.tell( :mark => ".", :message => "new symlink: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ ) if stat.symlink?
								#x.tell( :mark => ".", :message => "new #{stat.ftype} variant: #{base}/#{top}/#{name}", :file => __FILE__, :line => __LINE__ ) if verbose
								knowns << [base,stat,:keep]
								info[base][:new] += stat.size
								set.newsize += stat.size if base == newversion
								set.totalsize += stat.size
							end
							info[base][:total] += stat.size
						end
						case count
							when :files
								set.files += 1
							when :dirs
								set.dirs += 1
							when :sockets
								set.sockets += 1
							when :fifos
								set.fifos += 1
							when nil
							else
								raise "no such counter as #{count}"
						end
						info[base][count] += 1 unless nil == count
					end
				end
				recurse #returns to coiterate weather to recurse on this item
			end
		rescue Exception => e
			x.tell( :mark => "!", :message => "! BUG IN CLEANUP !", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			x.tell( :mark => " ", :message => "        context: #{root} + #{base} + #{top} + #{name}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			x.tell( :mark => " ", :message => "       iterator: #{errmsg}", :file => __FILE__, :line => __LINE__ )
			x.tell( :mark => " ", :message => "      set state: "+set.show, :file => __FILE__, :line => __LINE__ )
			m = e.message ? " => #{e.message}" : ""
			x.tell( :mark => " ", :message => "      exception: #{e.class}#{m}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
			x.tell( :mark => " ", :message => "      backtrace: ...\n\t"+e.backtrace.join("\n\t"), :file => __FILE__, :line => __LINE__ )
			x.tell( :mark => "!", :message => "the following metrics are incomplete", :file => __FILE__, :line => __LINE__ )
			ti[:exception]={:summary=>"Bug in Cleanup",:class=>e.class.to_s,:message=>e.message,:destination=>setdest,:source=>src,:context=>"#{root} + #{base} + #{top} + #{name}",:iterator=>errmsg}
		ensure
			x.tell( :mark => "-", :message => "#{set.totalsize} bytes in #{versions.length} versions of #{set.files} files in #{set.dirs} directories", :file => __FILE__, :line => __LINE__ )
			t = set.totalsize > 0 ? 100*set.newsize/set.totalsize : 0
			f = free > 0 ? 100*set.newsize/free : 100
			#x.tell( :mark => "-", :message => "#{set.newsize} new bytes in this version (#{t}% of all versions, #{f}% of available space)", :file => __FILE__, :line => __LINE__ )
			x.tell( :mark => "-", :message => "#{set.newsize} new bytes in this version (#{t}% of items in common with considered versions, #{f}% of available space)", :file => __FILE__, :line => __LINE__ )
			t = set.totalsize > 0 ? 100*set.saved/set.totalsize : 0
			f = free > 0 ? 100*set.saved/free : 100
			#w.tell( :mark => "-", :message => "#{set.saved} bytes freed in #{set.relinked} files relinked (#{t}% of all versions, #{f}% of available space)", :file => __FILE__, :line => __LINE__ )
			w.tell( :mark => "-", :message => "#{set.saved} bytes freed in #{set.relinked} files relinked (#{t}% of items in common with considered versions, #{f}% of available space)", :file => __FILE__, :line => __LINE__ )
			#free = "df -B 1 #{root.cmdsafe} | tail -n 1 | awk \'/.*\\n*\\s*\\n*\\s*\\n*.*/ { if ( $1 !~ /\\// ) print $3; else print $4 }\'"
			#free = `#{free}`.to_i
			#puts " - #{free} bytes free after cleaning"
			unless nil==ti[:exception]
				ti[:stats]={:snapshots=>versions.length,:files=>set.files,:dirs=>set.dirs,:bytes_total=>set.totalsize,:bytes_new=>set.newsize,:relinked=>set.relinked,:bytes_relinked=>set.saved,:skip_sockets=>set.sockets,:skip_fifos=>set.fifos}
			end
		end
		stopset = Time.now
		x.tell( :mark => "-", :message => "done in #{startset.showdiff(stopset)} at #{stopset.strftime("%H:%M:%S")}", :file => __FILE__, :line => __LINE__, :promote => 1, :surpress => false )
		timeinfo[:sets][set.tag][:end_unix]=stopset.to_i; timeinfo[:sets][set.tag][:end_string]=stopset.strftime(_time_format);
	end
end
#versions[-1][1] = File.stat( File.join( root, versions[-1][0] ) ) #refresh stat of new version
versions[0][1] = File.stat( File.join( root, versions[0][0] ) ) #refresh stat of new version
endtime=Time.now
timeinfo[:snapshot][:end_unix]=endtime.to_i; timeinfo[:snapshot][:end_string]=endtime.strftime(_time_format)

#exit

w.tell( :surpress => true, :mark => "*", :message => "+ Pathes in old versions", :file => __FILE__, :line => __LINE__ )
w.tell( :surpress => true, :mark => "X", :message => "(pathes report not yet implemented)", :file => __FILE__, :line => __LINE__ )

w.tell( :surpress => true, :mark => "*", :message => "* * Backup Summary by Age", :file => __FILE__, :line => __LINE__ )
w.tell( :surpress => true, :mark => ".", :message => "(needs to be merged into a column in the final summary)", :file => __FILE__, :line => __LINE__ )  ## TODO: !

#nextv = -1
nextv = 0
checkv = versions[nextv]
#iend = checkv[1].mtime
iend = checkv[2]  #use .startat
backupintervals.each_index do |i|
	nexti = backupintervals[i+1]
	thisi = backupintervals[i]
	unless nil == nexti then
		istart = iend.adjust( nexti[:units], -nexti[:interval] ).adjust( thisi[:units], -thisi[:interval] )
	else
		istart = nil
	end
	nextbreak = iend.adjust( thisi[:units], -thisi[:interval] )
	while true do
		thisbreak = nextbreak #next break time is determined during loop
		thisbreak = istart if nextbreak < istart unless nil == istart #break at end of larger interval, when encountered
		thisint = []
		while true do #get versions newer than the break
			checkv = versions[nextv]
			#puts "#{nextv}: #{checkv[0]} @ #{checkv[1].mtime}"
			break if nil == checkv
			#break if checkv[1].mtime < thisbreak
			break if checkv[2] < thisbreak
			thisint << checkv
			#nextv -= 1
			nextv += 1
		end
		unless 0 == thisint.length then #if there are versions newer than the break:
			w.tell( :surpress => true, :mark => "*", :message => "* #{thisi[:part]} ending #{thisbreak.adjust(thisi[:units],thisi[:interval]).strftime($dateout)}: #{thisint.length} backups:", :file => __FILE__, :line => __LINE__ )
			thisint.each_with_index do |backup,index|
				#puts " -\t#{index+1}:  #{backup[0].inspect} - finished at #{backup[1].mtime.strftime($dateout)}"
				w.tell( :surpress => true, :mark => "-", :message => "#{index+1}:  #{backup[0].inspect} - finished at #{backup[2].strftime($dateout)}", :file => __FILE__, :line => __LINE__ )
			end
			#nextbreak = thisint[-1][1].mtime.adjust( thisi[:units], -thisi[:interval] ) #next break is an interval after the last version before this break
			nextbreak = thisint[-1][2].adjust( thisi[:units], -thisi[:interval] ) #next break is an interval after the last version before this break
		else #if there are no versions newer than the break:
			#puts "\n * * empty #{thisi[:part]} ending #{thisbreak.strftime($dateout)}"
			#nextbreak = checkv[1].mtime unless nil == checkv #if this period is empty, start the next period where it will end at the time of the next backup
			nextbreak = checkv[2] unless nil == checkv #if this period is empty, start the next period where it will end at the time of the next backup
		end
		#puts "next #{thisi[:part]} ends #{nextbreak.strftime($dateout)}"
		break if nil == checkv
		break if istart >= nextbreak unless istart == nil
	end
	break if nil == checkv
	iend = istart.adjust( thisi[:units], thisi[:interval] ) unless nil == istart
end

w.tell( :surpress => true, :mark => "*", :message => "* * Backup Summary by Size", :file => __FILE__, :line => __LINE__ )

report = Sample.new( "files", "dirs", "new", "n%", "total", "change", "c%" )

pname = nil
#relinked = 0
savemax = 0

ignorenew = [] if nil == ignorenew
versions.reverse_each do |name,stat,start| # report oldest first
	f = info[name][:files]
	d = info[name][:dirs]
	n = info[name][:new]
	t = info[name][:total]
	if nil == pname or ignorenew.include?(name)
		n = v = "(n/a)"
		pn = pv = "-"
	else
		pt = info[pname][:total]
		if 0 == pt then
			pv = pn = 100
			v = t
		else
			pn = (100 * n.to_f/pt).round
			v = t-pt
			pv = (100 * v.to_f/pt).round
		end
	end
	pname = name
	report << [name,f,d,n,pn,t,v,pv]
	#relinked += info[name][:relinked]
	savemax = info[name][:saved] if info[name][:saved] > savemax
end

w.tell( :surpress => true, :mark => ":", :message => "Snapshot size table (of items in common with considered versions): ...\n"+report.report, :file => __FILE__, :line => __LINE__ )

if 1 >= versions.length then #this is the first run
	used = report.high("total")
	free = "df -B 1 #{root.cmdsafe} | tail -n 1 | awk \'/.*\\n*\\s*\\n*\\s*\\n*.*/ { if ( $1 !~ /\\// ) print $3; else print $4 }\'"
	free = `#{free}`.to_i
	free = 0 if free < 0

	report = Sample.new(nil)
	report << ["size of initial snapshot",used]
	report << ["apparent current space free",free]
	w.tell( :mark => ":", :message => "Usage Summary: ...\n"+report.report(false), :file => __FILE__, :line => __LINE__ )
else
	high = report.high("new") # biggest version
	new = 0.01*report.mean("n%")*high # expected new portion
	change = 0.01*report.mean("c%")*high # expected size increase
	change = 0 if change < 0 # no negatives
	safe = (new+change).ceil # expected maximum size of next version
	safe += savemax*report.mean("c%") # plus expected maximum transient usage
	free = "df -B 1 #{root.cmdsafe} | tail -n 1 | awk \'/.*\\n*\\s*\\n*\\s*\\n*.*/ { if ( $1 !~ /\\// ) print $3; else print $4 }\'"
	free = `#{free}`.to_i
	free = 0 if free < 0

	report = Sample.new(nil)
	report << ["estimated free space needed for next backup",safe]
	report << ["apparent current space free",free]
	report << ["extra free space available",free-safe] if free >= safe
	report << ["additional free space needed",safe-free] if safe > free
	w.tell( :mark => ":", :message => "Usage Summary: ...\n"+report.report(false), :file => __FILE__, :line => __LINE__ )
end

tname = File.join( dest, "timeinfo" )
w.tell( :mark => ".", :message => "storing timeinfo in #{tname}", :file => __FILE__, :line => __LINE__ )
File.open( tname, "wb" ) { |f| f.puts timeinfo.to_yaml }

w.tell( :mark => "*", :message => "* All Done in #{startat.showdiff}", :file => __FILE__, :line => __LINE__ )
file_unlock( lockfile )



