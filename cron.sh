#!/bin/bash

echo "--- RAID Status:"
cat /proc/mdstat
echo
echo "--- LVM Status:"
/sbin/lvs
echo
echo "--- Utilization:"
df -B 1 /volumes/backup/
echo

_here=`realpath \`dirname "$0"\``
#echo "_here=$_here"
_output=~/tmp/backshot.`date +\%A`.output
#echo "_output=$_output"
if [ -e $_output ]; then rm $_output; fi

"$_here/backshot.rb" >> $_output 2>&1

_errors=`grep -Ei "error|fail|bug|errno" $_output | wc -l`

echo
#echo $_output
echo "--- BackShot Output (seems to have $_errors errors):" 
echo
cat $_output
echo
#echo $_output
echo "--- All Done (seemed to have $_errors errors)."
echo

rm $_output

