#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8

# === backshot/ext.rb
# Standard library extensions for BackShot
#
# Author::    Shad Sterling <mailto:me@shadsterling.com>
# Copyright:: Copyright (c) 2005-2018 Shad Sterling
# License::   AGPL

class Object
	#"safe" dup; won't raise on singleton/non-dupable objects
	def sdup
		begin
			dup
		rescue
			self
		end
	end
end

class String
	#make a string safe to use in a system call - this means don't use quotes around it
	def cmdsafe
		s = self.sdup
		s.gsub!("\\"){"\\\\"} #this is in a block because gsub is broken
		s.gsub!("\"","\\\"")
		s.gsub!("\'"){"\\\'"} #this is in a block because gsub is broken
		s.gsub!("`"){"\\`"} #this is in a block because gsub is broken
		s.gsub!(" ","\\ ")
		s.gsub!("$","\\$")
		s.gsub!("\&","\\\\\\&") #something's broken here too
		s.gsub!("(","\\(")
		s.gsub!(")","\\)")
		s.gsub!("<","\\<")
		s.gsub!(">","\\>")
		s.gsub!("|","\\|")
		s.gsub!(";","\\;")
		s.gsub!("!","\\!")
		s.gsub!("\*","\\*")
		s
	end
end

class Time
	#generate a string saying how many days, hours, minutes, and seconds are between this time and another time
	def showdiff( to=Time.now )
		op = ""
		left = (to - self) / (60*60*24)
		#print " from #{self} to #{to}: #{left.inspect};"
		days = left.floor
		op << " #{days} days" if days > 0
		left = (left-days)*24; hours = left.floor
		op << " #{hours} hours" if hours > 0
		left = (left-hours)*60; minutes = left.floor
		op << " #{minutes} minutes" if minutes > 0
		left = (left-minutes)*60; seconds = (left.to_f * 10000.0).round / 10000.0
		op << " #{seconds} seconds" if seconds > 0 or "" == op
		#puts "#{op}"
		op[1..-1]
	end
	#returns a new Time, with the day, month, etc., adjusted
	def adjust( what, by )
		from = self.to_a
		#puts "#{what} #{by}: #{from.inspect} <- #{self}"
		date = from[3..5].reverse
		case what
			when :day
				from[3] += by
				date = from[3..5].reverse
				if 0 >= from[3] then
					until 0 < from[3] do
						badday = from[3] #bad day, like -1
						#puts "#{what} #{by}: #{from.inspect} -> invalid day #{badday}"
						from[3] = 1 #clear day to get something valid
						from = Time.local(*from).adjust( :month, -1 ).to_a #update from to the previous month - recurse to deal with year boundary
						date = from[3..5].reverse #re-get date part in previous month
						date[2] = 31 #find the end of the previous month
						until Date.valid_date?( *date ) do
							date[2] -= 1
						end #date[2] is now the last day of the previous month, like 30
						#puts "#{what} #{by}: #{from.inspect} -- end of previous month is #{date[2]}"
						from[3] = badday + date[2] #from[3] is now the correct offset from the beginning of the previous month
						#puts "#{what} #{by}: #{from.inspect} <- went back to #{from[3]}"
					end
				else
					until Date.valid_date?( *date ) do # day has been incremented past end of month
						badday = from[3] #bad day, like 32
						#puts "#{what} #{by}: #{from.inspect} -> invalid day #{badday}"
						from[3] = 1 #clear day to get something valid
						from = Time.local(*from).adjust( :month, 1 ).to_a #update from to the next month - recurse to deal with year boundary
						until Date.valid_date?( *date ) do #note that date still reflects the original month
							date[2] -= 1
						end #date[2] is now the last day of the month, like 31
						#puts "#{what} #{by}: #{from.inspect} -- last valid day is #{date[2]}"
						from[3] = badday - date[2] #from[3] is now the number of days by which the day went past the end of the month
						#puts "#{what} #{by}: #{from.inspect} <- went over by #{from[3]}"
						date = from[3..5].reverse
					end # loop because by could be longer than a month
				end
			when :month
				from[4] += by
				date = from[3..5].reverse
				if 0 >= from[4] then
					until 0 < from[4] do
						badm = from[4] #bad month, like -1
						#puts "#{what} #{by}: #{from.inspect} -> invalid month #{badm}"
						from[4] = 1 #clear month to get something valid
						from = Time.local(*from).adjust( :year, -1 ).to_a #update from to the previous year
						from[4] = badm + 12 #from[3] is now the correct offset from the beginning of the previous year
						#puts "#{what} #{by}: #{from.inspect} <- went back to #{from[4]}"
					end
				else
					until 13 > from[4] do # month has been incremented past end of year
						badm = from[4] #bad month, like 13
						#puts "#{what} #{by}: #{from.inspect} -> invalid month #{badm}"
						from[4] = 1 #clear day to get something valid
						from = Time.local(*from).adjust( :year, 1 ).to_a #update from to the next year
						from[4] = badm - 12 #from[4] is now the number of months by which the month went past the end of the year
						#puts "#{what} #{by}: #{from.inspect} <- went over by #{from[4]}"
					end # loop because by could be longer than a year
				end
			when :year
				from[5] += by
			else
				raise "no such interval as #{what}"
		end
		#print "#{what} #{by}: #{from.inspect} -> "
		begin
			r = Time.local( *from )
		rescue
			puts "unable to create time from #{from.inspect} after #{what} #{by}"
			r = Time.local( *from )
		end
		#puts r
		#puts "#{r}; #{r.inspect}"
		r
	end
	def self.strptime_local( str, fmt )
		#date = Date::strptime( str, fmt )
		#return Time.gm( date[:year], date[:mon], date[:mday], date[:hour], date[:min], date[:sec])
		date = DateTime::strptime( str, fmt )
		return Time.local( date.sec, date.min, date.hour, date.mday, date.mon, date.year, date.wday, date.yday, Time.now.dst?, date.zone )
	end
	def self.strptime_local_dst( str, fmt )
		#date = Date::strptime( str, fmt )
		#return Time.gm( date[:year], date[:mon], date[:mday], date[:hour], date[:min], date[:sec])
		date = DateTime::strptime( str, fmt )
		return Time.local( date.sec, date.min, date.hour, date.mday, date.mon, date.year, date.wday, date.yday, !Time.now.dst?, date.zone )
	end
end

class File::Stat
	def fifo?
		"fifo" == ftype
	end
end

class Array
	def thin_decay( count )
		count = count.floor # must be an integer
		return [] if 0 >= count # zero or fewer is empty
		return [self[0]] if 1 == count # just one is self[0]
		return dup if length <= count # don't thin when already short enough
		match = count...(0.5+count) # acceptable range for count calculated from decay factor
		max = 1.0 # max decay factor
		min = 0.0 # min decay factor
		f = c = nil # ensure scope
		100.times do # never do more than 100 iterations
			f = (max+min)/2 # estimated decay factor
			c = (f**length - 1)/(f-1) # count from estimated decay factor - sum from i=0 to i=n-1 of f**i
			#puts "#{f} => #{c} target #{match}"
			break if match.cover? c # calculates count in acceptable range means acceptable f found
			if count > c
				min = f # low count means factor estimate is too low
			else # count < c
				max = f # high count means factor estimate is too high
			end
		end
		raise "<Array length=#{length}>.thin_fading(#{count}) failed to find an acceptable decay factor after 100 iterations" unless match.cover? c
		p = 1.0
		r = Array.new(count)
		i = 0
		0.upto(length-1) do |j|
			if rand < p
				r[i] = self[j]
				i += 1
			end
			#puts "#{j}(#{length-j-1}):  #{p}  => #{i-1}(#{count-i})"
			if count <= i # count met
				break # done
			elsif (count-i) == (length-j-1) # only enough remaining to meet count
				p = f = 1 # force inclusion of all remaining
			else # normal
				p *= f # adjust probability by decay factor
			end
		end
		raise "<Array length=#{length}>.thin_fading(#{count}) ended with actual count #{i}" unless count == i
		return r
	end
end
