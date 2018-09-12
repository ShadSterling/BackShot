#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8

require 'fileutils'


def file_lock( lock_file = File.join( File.dirname($0), "lock.#{File.basename($0)}" ),
          expiration_age = 1*60*60,
          force_age = nil
        )

	lock_pid = lock_age = pid_info = nil
	status = :bug
	message = "BUGGED OUT!"
	if File.file?( lock_file ) then #already locked
		begin
			lock_age = Time.now - File.stat(lock_file).mtime #seconds since lock
			lock_pid = File.read(lock_file).to_i
			pid_info = `ps -Fp #{lock_pid}`.chomp; #sets exit status to 1 if the process is not running
			pid_dead = (1 == $?.exitstatus)
			if pid_dead then #process is not running - ok to break lock
				File.unlink( lock_file )
				status = :died
				message = "Locked by dead process - Lock removed"
			elsif lock_age > expiration_age then #locked and expired
				if (nil != force_age) and (lock_age > force_age) #process is running and should be forced
					File.unlink( lock_file )
					status = :forced
					message = "Locked by old process, Force age exceeded (#{lock_age} > #{force_age}) - Lock removed"
				else #process is running and expired
					status = :expired
					message = "Locked by old process, Expiration age exceeded (#{lock_age} > #{expiration_age}) - Lock preserved"
				end
			else  #locked, process is running and not expired
				status = :running
				message = "Locked by active process - Lock preserved"
			end
		rescue Errno::ENOENT
			status = :vanished
			message = "Lock file vanished before status could be tested"
		end
	else  #not locked
		lock_pid = $$
		lock_age = 0 #seconds since lock
		pid_info = `ps -Fp #{lock_pid}`; #we know this process is running!
		File.open(lock_file, 'wb') do |f| f.puts lock_pid; end
		status = :created
		message = "New lock established"
	end
	[ status, lock_pid, lock_age, pid_info, message ]

end

def file_unlock( lock_file = File.join( File.dirname($0), "lock.#{File.basename($0)}" ) )
	File.unlink( lock_file )
end