#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8
#
#---------#---------#---------#---------#---------#---------#---------#---------#---------#---------#
#++
#
# === backshot/show.rb
# Simple intelligible string representation of most intrinsic types
#
# Author::    Shad Sterling <mailto:me@shadsterling.com>
# Copyright:: Copyright (c) 2005-2010 Shad Sterling
# License::   AGPL
#
#
# less-verbose substitutes for inspect, which I made so that I could debug
# more effectively than with inspect
#
# adds show and showall to Object, Array, Hash, String, NilClass, Symbol,
# and Float
#
#


# The Parent of all objects -- things that must work everywhere are defined here.
class Object

	# A higher-level (and less rigerous) "inspect", showing the values without the classes or ids.
	# - v is used to limit the maximum nesting depth.  When anObject.show calls anotherObject.show,
	#   it passes v-1; if v < 0, it will not make the call.
	def show( v=0 );
		to_s || inspect
	end

	# Like Object#show, using multiple lines to show structure.
	# Strings returned by #showall always end with "\\n"
	# - d is the current nesting depth; it is used for indentation and for limiting nesting.
	#   When anObject.showall calls anotherObject.showall it passes d+1.
	# - m is the maximum nesting depth.  When d == m, anObject.showall will call
	#   anotherObject.show(1), otherwise is calls anotherObject.showall and passes m unchanged.
	def showall( d=0,m=-1 ); "#{show}\n"; end
end

# Some of the methods I define for Object don't work correctly for Array, so I overload them
class Array

	# A higher-level (and less rigerous) "inspect", just showing the values without the classes or ids.  For Array, the entries are shown.
	# - v is used to limit the maximum nesting depth (see Object#show)
	def show( v=0 )
		return "[]" if length == 0
		return "[..#{self.length}..]" if v < 0
		r = "[ "
		each { |i| r << i.show(v-1) << ", " }
		r[-2..-1] = " ]"
		r
	end

	# Like Array#show, but not all on one line.
	# - d and m are used to limit the maximum nesting depth (see Object#showall)
	def showall( d=0, m=-1 )
		r = "[ "
		return "[]\n" if length == 0
		f = true
		each { |i|
			if f == true then
				f = false
			else
				r << "  #{"  "*d}"
			end
			if d == m then
				r << "#{i.show(1)}\n"
			else
				r << "#{i.showall(d+1,m)}"
			end
		}
		r[-1] = " ]\n"
		return r
	end
end

# Some of the methods I define for Object don't work correctly for Hash, so I overload them
class Hash

	# A higher-level (and less rigerous) "inspect", just showing the values without the classes or ids.  For Hash, the entries are shown.
	# - v is used to limit the maximum nesting depth (see Object#show)
	def show( v=0 )
		return "{}" if length == 0
		return "{..#{self.length}..}" if v < 0
		r = "{ "
		each { |i|
			if i.length > 2 then
				r << i.show(v-1) << ", "
			else
				r << "#{i[0].show(v-1)}"
				if i[1] != true then
					r << " => #{i[1].show(v-1)}"
				end
				r << ", "
			end
		}
		r[-2..-1] = " }"
		r
	end

	# Like Hash#show, but not all on one line.
	# - d and m are used to limit the maximum nesting depth (see Object#showall)
	def showall( d=0, m=-1)
		r = ""
		case length
			when 0
				r = {}
			when 1
				if d == m then
					r = "{ #{keys[0].show(1)} => #{values[0].show(1)} }"
				else
					r = "{ #{keys[0].showall(d+1,m).chomp} => #{values[0].showall(d+1,m).chomp} }"
				end
			else
				r = "{\n"
				dent = "#{"  "*d}"
				if d == m then
					each do |key,value|
						r += "#{dent}  #{key.show(1)} => #{value.show(1)}\n"
					end
				else
					each do |key,value|
						r += "#{dent}  #{key.showall(d+1,m).chomp} => #{value.showall(d+1,m).chomp}\n"
					end
				end
				r += "#{dent}} "
		end
		return r
	end

	# Like Hash#show, but not all on one line.
	# - d and m are used to limit the maximum nesting depth (see Object#showall)
	def showall_classic( d=0, m=-1)
		r = "{ "
		return "{}\n" if length == 0
		f = true
		each { |i|
			if f == true then
				f = false
			else
				r << "  #{"  "*d}"
			end
			if i.length > 2 then
				r << i.show(1) << ", "
			else
				r << "#{i[0].show(1)}"
				if i[1] != true then
					if d == m then
						r << " => #{i[1].show(1)}\n"
					else
						r << " => #{i[1].showall(d+1,m)}"
					end
				else
					r << "\n"
				end
			end
		}
		r[-1] = " }\n"
		return r
	end
end

# String manipulation
class String
  # show strings in quotes
	def show v=0
		"\"#{self}\""
	end
end

class NilClass
  # show "<nil>"
	def show v=0
		"<nil>"
	end
end

class Symbol
  # show symbols with the :
	def show v=0
		":#{self}"
	end
end

class Float
	# make sure the ".0" is shown for floats
	def show(v=0)
		if self.respond_to?("to_s_notrim") then
			to_s_notrim
		else
			to_s
		end
	end
end


