# backshot.rb
Snapshot-style cross-linking directory tree backups

Creates backup snapshots which are ordinary directory trees, with identical files cross-linked to save space.

For each source path in a backup set, a copy of the full tree from that point is created at the corresponding path in the snapshot; when a file is identical to the same relative path in any previous snapshot, the entry in the new snapshot is a hard link to the entry in that previous snapshot.  Subdirectories are traversed.  Symlinks are backed up as symlinks, they are never followed.  Sockets and fifos are omitted. All other types (notably regular files and devices) are duplicated using tools appropriate to each backup set.

Storing backups as regular files in ordinary directory trees means no special tools are needed to access, remove, or modify backups.  (Special tools may still add convenience.)  If you want better storage efficiency at the expense of not storing snapshots on the regular filesystem, use BackupPC: <https://backuppc.github.io/backuppc/>.

When file metadata changes but file content does not, changes to the inode-associated metadata is not preserved in the new snapshot; the new snapshot contains a link to the older inode.  If you want to spend the storage space to make an additional copy of such files in order to preserve all metadata, use rsnapshot: <http://rsnapshot.org/>.

If you are running on OS X you must supply Linux-style `df` and `cp` commands;for example, install [macports](https://www.macports.org/) coreutils, and put `/opt/local/libexec/gnubin` first in the path.  If you are backing up user home directories, you will likely want to exclude `~/.gvfs` for each user.  If the filesystem your snapshots are stored on supports `lchmod` and/or `lchown`, you should enable those features in your configuration.  If you synchronize your userlists, ownership and permissions in the backup will match the source.  If not, the ownership and permissions might be confusing, but the data will not be affected.

Some methods have `rdoc`-comments

## Configuration

Currently, the configuration must be loaded from `config.rb` in the same directory as `backshot.rb` (see [TODOs](#pre-github-todo-list)).  Most values have no defaults, so the boilerplateitems must be included.

Example configuration:

```ruby
#!/usr/bin/ruby1.9 -wKU
# encoding: UTF-8

{
	:superuser => :maybe,
	:mountroot => "/mnt",  # used for remote sets with no specified mountpoint, creates "#{$mountroot}/#{foo}"; no remote sets in this example
	:prefix => ".#BackShot.#{$$}#.", # prefix for temp file names
	:dateout => "%a %Y-%b-%d %H:%M:%S (%Z)",
	:root => "/volumes/backup/versions",
	:verbose => true,
	:thinning => 27, # when hardlinking from new snapshot to old snapshot, only consider this many old snapshots (after a few years of nightly backups, the long list makes things slow); chooses at random, with more recent snapshots more likely and most recent always included
	:backupsets => [
		{ #0
			:name => "Localhost Configuration",
			:tag => "etc",
			:source => "/etc/",
			:target => "hosts/localhost/etc",
		},
		{ #1
			:name => "Localhost Superuser",
			:tag => "root",
			:source => "/root/",
			:target => "hosts/localhost/superuser",
			:exclude => [ "/.Trash/***", "/.npm/***", "/.local/***", "/tmp/***", "/Library/***", ],
		},
		{ #2
			:name => "Mirrorhost Configuration",
			:tag => "mirrorhost",
			:source => "/volumes/backup/sourcemirror/mirrorhost/etc/",
			:target => "hosts/mirrorhost/etc",
			:exclude => [ "/cups/certs/***", ],
		},
		{ #3
			:name => "Mirrorhost Superuser",
			:tag => "root",
			:source => "/volumes/backup/sourcemirror/mirrorhost/root/",
			:target => "hosts/mirror/superuser",
			:exclude => [ "/.Trash/***", "/.npm/***", "/.local/***", "/tmp/***", "/Library/***", ],
		},
		{ #4
			:name => "Username's Home Directory",
			:tag => "username",
			:source => "/home/username/",
			:target => "users/Username/Home",
			:exclude => [
				#expendable
				"/Documents/Downloads/***",
				"/Downloads/***",
				#oversize
				"/VirtualBox VMs/***",
				#inaccessable
				"/.gvfs/***",
				#trash
				"/Documents/RECYCLER/***",
				"/.Trash/***",
				#temp
				"/tmp/***",
				"/.wine/drive_c/windows/temp/***",
				".unison.*.unison.tmp",
				".node-gyp/***",
				#cache
				"/.cache/***",
				"/.winetrickscache/***",
				"/.electricsheep/***",
				"/.thunderbird/*.profile/ImapMail/***",
				"/.dvdcss/***",
				"/.npm/***",
				"/.config/xbuild/***",
				#reinstall
				"/.wine/drive_c/Program Files/***",
				"/.wine/drive_c/windows/system32/***",
				"/Applications/***",
				"/.npm-global/***",
				"node_modules/",
				#regenerates
				"/.unison/ar*",
				"/.local/***",
				"/.p2/***",
				"/.macromedia/***",
				"/.xsession-errors*",
				"/.eclipse/***",
				"/.config/configstore/update-notifier-npm.json",
				"/hosts/*/var/sync/time",
				#host app states
				"/.gstreamer-*/***",
				"/.x2go/***",
				"/.xnviewmp/***",
				"/Documents/Microsoft User Data/***",
				"/.config/deluge/***",
				"/.avidemux6/***",
				"/.mozilla/***",
				"/.mono/***",
				#backups
				"/.unison/backup/***",
			],
		},
	],
	:backupintervals => [
		{
			:name => "daily",
			:part => "day",
			:interval => 1,
			:units => :day,
		}, {
			:name => "weekly",
			:part => "week",
			:interval => 7,
			:units => :day,
		}, {
			:name => "monthly",
			:part => "month",
			:interval => 1,
			:units => :month,
		}, {
			:name => "quarterly",
			:part => "quarter",
			:interval => 3,
			:units => :month,
		}, {
			:name => "annually",
			:part => "year",
			:interval => 1,
			:units => :year,
		},
	],
}
```


## License

BackShot - snapshot-style cross-linking directory tree backups<br/>
Copyright © 2005-2018 Shad Sterling <<me@shadsterling.com>>

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU Affero General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along with this program.
If not, see <http://www.gnu.org/licenses/agpl.html>


## Pre-Github TODO list

- option to show progress / current file during backup
  - show running count and expected total (%?) for reference
- show times for each step (at least when verbose)
- redundency tracking:
  - load from all prior versions on start; path => redundent-with
    - when redundancy information is missing, regenerate for two oldest for which it is missing
  - in coiterate, skip branches redundant with existing version (do not skip when redundant with versions which have dissapeared)
  - when all entries in a directory are redundant with the same version, the directory is redundant with that version
  - when a directory is not redundant but has subdirectories that are, add the subdirectories to the tracking list
  - store tracking list at finish
  - add columns to final report: age, some redundency metric (maybe prune count & graph count)
- split out configuration file (search /etc/backshot.conf, /etc/sysconfig/backshot, ./backshot.conf)
- add options for lchmod & lchown
  - absent or unrecognised value means no; "yes", "true", "attempt", "implemented", etc mean yes
- document dependencies
- better handling of lock status
- do the "Pathes in old versions" report (sets which have been removed)
- OOify
- improve report:
  - replace field labels with column headers
  - save to csv
  - split file/dir/symlink to multiple columns each e.g. all, new, changed, moved, unchanged
- perform multiple sets concurrently
  - force separate host field in set description
  - add concurrency options; default to max 10 concurrent, max 1 per host
- add emailing of individual logs to specified email address; add email field to backup set
- add features to help with thinning old backup versions
  - add options to describe thinning strategy, boundary alignment (alignment e.g. oldest version, newest version, nearest year boundary, specified datetime, ...)
  - add columns with purge information - purge time, status (never, soon, due, overdue, ...)
  - add option to automatically purge
- add moved file detection & crosslinking:
  - load checksum lists on start
    - when checksum information is missing, regenerate for two oldest for which is it missing
  - checksum every newfile; check against checksum list
    - whem a match is found, full diff & relink if matched
  - store new checksums & moved list at finish
  - give notice (not error) on equal checksums for different files
    - generate binary diff of files; request email that file to me
- confirm ACLs are backed up correctly.
- use tasktime to support individual scheduling per set
- take advantage of snapshot features of source storage, e.g. LVM
- Add support for 'bare metal' backup & restore
- add security features; over-the-wire-encryption, cooperation with encrypting FS, ...
- when file operations fail, show/log stat info for all files involved
- when operation fails on symlink, show target
- 2010-Nov.-26: Show largest changed file in each set
- 2011-June-03: show command start and finish times:
  - [stamp] - description of what command is for
  - [stamp] > command
  - [stamp] < exit code, output measures
- 2011-June-03: flush output before and after commands
- 2011-June-03: include all command output in logs (separate files; popen4?)
- 2011-June-03: include change count tree in logs
- 2011-June-04: flush output on clock
- 2011-June-04: touch version dir on finish; touch set dirs on finish
- 2011-June-05: move to storing setlist in versionroot, invoke with versionroot path
- 2011-June-05: add logs with $(du)-like usage summary, and with file-count summary
- 2011-June-07: add error summary at end of output
- 2011-June-11: implement the "paths in old versions" report
- 2011-June-18: add block support to lockfile (handle exceptions appropriately)
- 2011-July-08: validity checking on set tag before using in filename
- 2011-July-08: Change verbose setting to mean *additional* detailed logs with tracking are created
- 2011-July-08: Rewrite tell.rb promotion/surpression; needs a simple way to log-only in deep branches & output when promoted to a threshold
- 2011-July-08: Add hostname and config title to config; bail at start on hostname mismatch.
- 2011-July-08: add time offset to log timestamp
- 2011-July-08: special handling of filenames which look like temporary names used in relink()
- 2011-July-09: parse command output for errors; represent errors in logs
- 2011-July-09: store times for paths that take more than some threshold to process; use to estimate time required for new snapshot
- 2011-July-10: shell commands: distinguish command not found from nonzero return
- 2011-July-31: configuration editing tools - e.g. change target and preserve hardlinks
- 2011-July-31: config tools: templates e.g. for user homedirs to exclude .gvfs, tmp, etc.
- 2011-July-31: browse & restoration tools
- 2011-July-31: documentation
- 2011-July-31: [  tell.rb  ] - methods to branch a new thread with a corresponding log branch
- 2011-Aug.-06: tools - purge files/pathes from existing snapshots; remove from set & purge from snapshots; e.g. remove all desktop.ini, .DS_Store
- 2011-Aug.-06: [     ?     ] - option to mark new snapshots as readonly; actions on old snapshots don't fail on readonly snapshots
- 2011-Aug.-19: [backshot.rb] - notify when most recent backup did not complete (timeinfo has more start times than end times); other appropriate action?
- 2011-Aug.-19: [backshot.rb] - add time information to report(s)
- 2011-Aug.-28: [backshot.rb] - switch from unix/UTC timestamps to TAI timestamps; use leapsecond lists for conversion
- 2011-Sep.-03: [backshot.rb] - test-run switch to show output without writing to filesystem
- 2011-Sep.-03: [library.rb ] - need a BackupSet#show better than #inspect (used at BUG IN CLEANUP)
- 2011-Sep.-18: [backshot.rb] - count symlinks separately from regular files
- 2011-Sep.-18: [backshot.rb] - write timeinfo at start and update throughout
- 2011-Oct.-01: [backshot.rb] - regenerate old timeinfo when contents are invalid
- 2011-Nov.-06: [backshot.rb] - snapshot: if one but not all times on a file is set to epoch, set to earliest time field on that file
- 2011-Nov.-19: [library.rb ] - coiterate: switch to depth-first bottom-up order (top-down obscures failure point)
- 2011-Nov.-21: [backshot.rb] - switch to YAML configuration; check all entries at load-time
- 2011-Nov.-21: [backshot.rb] - create a status file computably indicating statistics & errors for each snapshot
- 2013-Mar.-19: [backshot.rb] - invocation should require a command, e.g. $(backshot snap) to make a new snapshot
- 2013-Mar.-19: [backshot.rb] - coiterated block should be split across two commands: one for making a new snapshot, another for optimizing crosslinks between old snapshots
- 2013-Mar.-19: [backshot.rb] - add command to remove from old snapshots files which have been excluded from new snapshots
- 2013-Mar.-20: [library.rb ] - relink: complete recovery instructions for all exception handlers
- 2013-Mar.-24: [     ?     ] - document status of metadata on crosslinked files before & after new snapshot creation; make sure the result makes sense, esp. for inode metadata; see e.g. oreilly.com/catalog/linuxkernel2/chapter/ch17.pdf#page=10
- 2014-Oct.-08: [     ?     ] - support xattrs and ACLs
- 2014-Oct.-08: [     ?     ] - when hardlinking loses metadata, keep original metadata in info file
-  (lost date): [     ?     ] - don't limit linking to identical files with the same path; store hash tables to link with identical files in different paths
-  (lost date): [     ?     ] - Modernize with bundler etc

## Pre-Github Changelog

- 2018-Sep.-11 @ 0.0.4    {spontanious} [     *     ] - Cleaned up for github
- 2014-Oct.-03 @ 0.0.3.04 {spontanious} [backshot.rb] - surpressed stdout output of summaries by age and size (now output to logfile only)
- 2014-Oct.-0? @ 0.0.3.03 {spontanious} [  cron.sh  ] - added occurances of errno to error count
- 2013-Mar.-23 @ 0.0.3.02 {spontanious} [backshot.rb] - adjusted thinning so config[:thinning] is the count including the new snapshot
- 2013-Mar.-20 @ 0.0.3.02 {spontanious} [backshot.rb] - coiterated block: verbose mode: log all relinks; stop logging skipped absent items or symlink variants
- 2013-Mar.-19 @ 0.0.3.01 {spontanious} [backshot.rb] - coiterated block: skip items absent in new snapshot (with log message); revised output messages re summary values
- 2013-Mar.-18 @ 0.0.3.00 {spontanious} [backshot.rb] - revised output messages to reflect the non-inclusiveness of summary values
- 2013-Mar.-18 @ 0.0.3.00 {spontanious} [backshot.rb] - thinning existing versions list for coiteration to config[:thinning]
- 2013-Mar.-18 @ 0.0.3.00 {cpontanious} [backshot.rb] - reversed sort of versions lists to make thinning more convenient
- 2013-Mar.-18 @ 0.0.3.00 {spontanious} [  ext.rb   ] - added array thinning to support limiting which old backup sets are considered
- 2011-Dec.-04 @ 0.0.2.11 { very old  } <   none    > - removed meaningless todo item "clean up the backup set descriptors"
- 2011-Nov.-21 @ 0.0.2.11 {spontanious} [backshot.rb] - timeinfo: fixed crash saving invalid timeinfo after exception in cleanup phase (the exception class was being used, rather than the string containing its name)
- 2011-Nov.-21 @ 0.0.2.11 {spontanious} [bachshot.rb] - logging: reduced stdout on exception in cleanup phase (no change to log)
- 2011-Nov.-21 @ 0.0.2.11 {spontanious} [  show.rb  ] - showall: fixed layout bug in Hash#showall (complete rewrite)
- 2011-Nov.-21 @ 0.0.2.11 {spontanious} [backshot.rb] - locking: moved lockfile into destination; warning on config present
- 2011-Nov.-20 @ 0.0.2.10 {spontaneous} [backshot.rb] - timeinfo: fixed crash when loading corrupt timeinfo (discards & regenerates)
- 2011-Nov.-19 @ 0.0.2.9  { very old  } [library.rb ] - coiterate: now sorting names before iterating; still iterates in depth-first top-down order
- 2011-Nov.-13 @ 0.0.2.8  { very old  } [backshot.rb] - timeinfo: removed output on loading prior timeinfo (keeping output when timeinfo is missing)
- 2011-Nov.-06 @ 0.0.2.7  { very old  } [backshot.rb] - timeinfo: now saving regenerated timeinfo; reduced output on generation & regeneration
- 2011-Oct.-09 @ 0.0.2.6  { very old  } [library.rb ] - BackupSet: improved BackupSet#to_h
- 2011-Oct.-02 @ 0.0.2.6  { very old  } [backshot.rb] - timeinfo: reduced info on mount/unmount when there's nothing to do; reduced tell of load old timeinfo
- 2011-Oct.-01 @ 0.0.2.6  { very old  } [backshot.rb] - timeinfo: moved set information to :sets submap; added snapshot name to :snapshot submap
- 2011-Sep.-18 @ 0.0.2.5  { very old  } [backshot.rb] - timeinfo: added basic set information and step times
- 2011-Sep.-10 @ 0.0.2.4  { very old  } [backshot.rb] - loading timeinfo in place of .starttime when present; generating but not saving timeinfos for old snapshots
- 2011-Sep.-04 @ 0.0.2.3  {spontanious} [backshot.rb] - fixed warnings about shadowed variables in coiterate block (previous Ruby versions exported rather than shadowing)
- 2011-Sep.-04 @ 0.0.2.3  { very old  } [backshot.rb] - fixed path to timeinfo, now it's in the snapshot root; added timeinfo echo to log
- 2011-Aug.-28 @ 0.0.2.2  { very old  } [backshot.rb] - timeinfo now stores unix time serial and human-readable string; removed leading dot from filename
- 2011-Aug.-27 @ 0.0.2.1  { very old  } [backshot.rb] - storing timeinfo; need to load/generate using .starttime if present - note if .starttime seems regenerated; stop generating .starttime
- 2011-Aug.-19 @ 0.0.2.0  { very old  } [backshot.rb] - generating timeinfo; need to save, load, generate from .starttime, generate instead of .starttime
- 2011-July-21 @ unknown  { very old  } [backshot.rb] - logs need more refinement, reflected in separate tasks; closing task "branch logs for more detailed per-set logs"
- 2011-July-31 @ unknown  {spontanious} [backshot.rb] - autodetect superuser privileges
- 2011-July-10 @ unknown  {spontanious} [backshot.rb] - get shell return values (rather than the boolean returned by system())
- 2011-July-08 @ unknown  {  unknown  } [library.rb ] - relink now uses a teller for output
- 2011-July-08 @ unknown  {  unknown  } [  tell.rb  ] - fixed fencepost error in promotion counting; requires default promote nonnegative
- 2011-July-08 @ unknown  {  unknown  } [  tell.rb  ] - now calls .flush after every output and .sync=true when opening a file
- 2011-July-08 @ unknown  {  unknown  } [  tell.rb  ] - fixed setting & handling of default value for "surpress" parameter
- 2011-July-08 @ unknown  {  unknown  } [library.rb ] - BackupSet instances now have a "tag"; a short name used in log entries & log file names
- 2011-July-08 @ unknown  {  unknown  } [backshot.rb] - finished task: branch logs for more detailed per-set logs
- 2011-June-18 @ unknown  {  unknown  } [  tell.rb  ] - logfiles can be moved after creation; finished task: save log in version base
- 2011-June-12 @ unknown  {  unknown  } [backshot.rb] - updated for ruby 1.9; runs with output through tell, but logs in versionroot
- 2011-June-11 @ unknown  {  unknown  } [backshot.rb] - all normal output replaced with tells; levels unused and debug messages still in comments
- 2011-June-10 @ unknown  {  unknown  } [  tell.rb  ] - Tell class and Teller module complete
- 2011-June-07 @ unknown  {  unknown  } [  tell.rb  ] - simplified Tell class, nearly completed
- 2011-June-05 @ unknown  {  unknown  } [backshot.rb] - (rsync) dropped --link-dest; it's redundant with cleaning phase and with preceding cp -Plr
- 2011-June-05 @ unknown  {  unknown  } [backshot.rb] - began replacing output with tells
- 2011-June-05 @ unknown  {  unknown  } [  tell.rb  ] - primary infrastructure largely complete
- 2011-June-04 @ unknown  {  unknown  } [  tell.rb  ] - began log/output subsystem
- 2011-June-03 @ unknown  {  unknown  } [backshot.rb] - (rsync) always exclude backup root; (scp) warn about lost symlinks {old undated todo item}
- 2010-Nov.-25 @ unknown  {  unknown  } [backshot.rb] - uses .starttime for age in summary report
- 2010-Nov.-08 @ unknown  {  unknown  } [backshot.rb] - fixed creation of missing .starttime to use correct time
- 2010-Nov.-08 @ unknown  {  unknown  } [backshot.rb] - sorts prior version list by .starttime content (not by directory mtime)
- 2010-Nov.-08 @ unknown  {  unknown  } [backshot.rb] - creates .starttime for older versions when missing
- 2010-Nov.-08 @ unknown  {  unknown  } [  lock.rb  ] - added debugging/informative error messages; removed redundant contitional
- 2010-Nov.-08 @ unknown  {  unknown  } [  ext.rb   ] - added Time::strptime_local and Time::strptime_local_dst (timezones & dst can't be handled correctly because the Date and Time classes are incompatible!)
- 2010-Sep.-19 @ unknown  {  unknown  } <  unknown  > - Omits FIFOs (rather than bailing)
- 2010-Sep.-12 @ unknown  {  unknown  } <  unknown  > - Removed dependency on current dirctory
- 2010-Aug.-20 @ unknown  {  unknown  } <  unknown  > - Primitive lockfile
- 2010-Aug.-19 @ unknown  {  unknown  } <  unknown  > - Fixing bugs specific to initial run
- 2010-Aug.-18 @ unknown  {  unknown  } <  unknown  > - Adaptations for OS X, and to run as ordinary user
- 2010-Aug.-17 @ unknown  {  unknown  } <  unknown  > - actually runs with multiple files
- 2010-Aug.-16 @ unknown  {  unknown  } <  unknown  > - split into multiple files
- 2010-Aug.-15 @ unknown  {  unknown  } <  unknown  > - housekeeping, brought todo list into file
- 2010-Aug.-12 @ unknown  {  unknown  } <  unknown  > - merged personal variant with former job varient
