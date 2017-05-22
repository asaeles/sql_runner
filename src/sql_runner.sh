################################################################################
#
# SQL Runner
#  This shell script is inspired from a standard used in our company:
#   . There are 3 main large directories on the application server: Bin, Log
#     and Work (this one is used for input, done and output files).
#   . Under each directory there is one sub-directory for each SQL tool.
#   . The same directory structure should be replicated on the DB server.
#
#  So for a tool named "Foo Bar", the structure should be as follows:
#   Application server:
#    Tool path   :    $HOME/$BIN/FOO_BAR/foo_bar_v1.1.1.sql
#    Log path    :    $HOME/$LOG/FOO_BAR/*.*
#    Input path  :    $HOME/$WORK/FOO_BAR/INPUT/*.*
#    Done path   :    $HOME/$WORK/FOO_BAR/DONE/*.*
#    Output path :    $HOME/$WORK/FOO_BAR/OUTPUT/*.*
#   Database server:
#    Log path    :    $HOME/$LOG/FOO_BAR/*.*
#    Input path  :    $HOME/$WORK/FOO_BAR/INPUT/*.*
#    Output path :    $HOME/$WORK/FOO_BAR/OUTPUT/*.*
#
#  The script handles moving files between application and database servers
#   and then deletes files from database after SQL script finishes.
#  It automatically moves input files after the SQL script finishes to the
#   Done folder.
#  It also creates a simple log file in the tool path to write extra info
#   about running.
#  It passes all command line arguments to SQL*Plus command
#  It returns non-zero error codes for severe/SQL errors
#
#  Usage:
#   1) The SQL Runner script (this script) should be renamed to match the
#      name of the SQL script and placed in the tool directory, because it
#      depends on:
#       . The current path to deduce the script directory (FOO_BAR)
#       . It's own file name to deduce the SQL scripts name (foo_bar_v1.1.1.sql)
#   2) The variables set in the start of the script should be changed to match
#      the required features and the application server directories and the 
#      database server host-name/IP for SSH
#
# -----------------------------------------------------------------------------
#
# Author   :  Ahmad Sulaeman <asaeles@gmail.com>
# License  :  GNU General Public License v3.0
#
################################################################################

L=1 #If the scripts needs log folder set to 1 otherwise 0
O=1 #If the scripts needs output folder set to 1 otherwise 0
I=1 #If the scripts needs input/done folders set to 1 otherwise 0
LD="$HOME/LOG_DIR" #Local Log directry
WD="$HOME/WORK_DIR" #Local Work directory (will hold Input, Done and Ouput)
DB="DB_HOSTNAME" #Unix DB hostname or IP
CS="SQL_CONN_STRING" #user/pass@sid

basename $0 | sed "s|\.[^\.]*$||" | read SCRIPT_NAME
if [ $? != 0 ]; then echo "ERR: Cannot get script name\n"; return 1; fi
pwd | read p
dirname $0 | read d
cd $p/$d/
if [ $? != 0 ]; then pts; echo "ERR: Cannot get change to script directory\n"; return 1; fi
SCRIPT_PATH=`pwd`
cd -
lf="$SCRIPT_PATH/$SCRIPT_NAME.log"
>$lf
echo

pts() {
  date "+%Y/%m/%d %H:%M:%S" | read nts
  printf "$nts: " >>$lf
}

db_delete() {
    ssh $DB <<EOF 2>>$lf
      cd $1
      if [ \$? != 0 ]; then exit 1; fi
      rc=0
      ls -1 | while read ml; do
        sqlplus -s sysadm/sysadm <<EOS 1>/dev/null 2>/dev/null
          WHENEVER SQLERROR EXIT 1 ROLLBACK;
          WHENEVER OSERROR EXIT 2 ROLLBACK;
          EXEC utl_file.FREMOVE('$1','\$ml');
          EXIT;
EOS
        if [ \$? != 0 ]; then
          rm -rf \$ml
          if [ \$? != 0 ]; then ((rc=\$rc+1)); fi
        fi
      done
      if [ \$rc != 0 ]; then exit 1; else exit 0; fi
EOF
}

pts; echo "Started '$SCRIPT_NAME' shell script\n" | tee -a $lf

basename $SCRIPT_PATH | read SCRIPT_DIR
if [ $? != 0 ] || [ "S$SCRIPT_DIR" = "S" ]; then pts; echo "ERR: Cannot get current script directory\n" | tee -a $lf; return 1; fi
pts; echo "INFO: Script directory: '$SCRIPT_DIR'\n" >>$lf

l="$LD/$SCRIPT_DIR/"
o="$LW/$SCRIPT_DIR/OUTPUT/"
i="$LW/$SCRIPT_DIR/INPUT/"
d="$LW/$SCRIPT_DIR/DONE/"

pts; echo "INFO: Database host name: '$DB'\n" >>$lf

HOST=`hostname 2>>$lf` 2>>$lf
if [ $? != 0 ] || [ "H$HOST" = "H" ]; then pts; echo "ERR: Cannot get current host name\n" | tee -a $lf; return 1; fi
pts; echo "INFO: Current host name: '$HOST'\n" >>$lf

if [ $L = 1 ]; then pts; echo "INFO: Script has log\n" >>$lf; fi
if [ $O = 1 ]; then pts; echo "INFO: Script has output\n" >>$lf; fi
if [ $I = 1 ]; then pts; echo "INFO: Script has input\n" >>$lf; fi

sqlplus -s "$CS" <<EOF | read VER
  WHENEVER SQLERROR EXIT 1 ROLLBACK;
  WHENEVER OSERROR EXIT 2 ROLLBACK;
  SET PAGES 0;
  SELECT '_v' || version ver FROM mobinil.mobinil_registry WHERE script_name = '$SCRIPT_NAME';
  EXIT;
EOF
if [ $? != 0 ] || [ "V$VER" = "V" ]; then pts; echo "ERR: Cannot get '$SCRIPT_NAME' version\n" | tee -a $lf; return 1; fi
SCRIPT_SQL="$SCRIPT_PATH/$SCRIPT_NAME$VER.sql"
if [ ! -f $SCRIPT_SQL ]; then pts; echo "ERR: SQL script '$SCRIPT_SQL' not found!\n" | tee -a $lf; return 1; fi
pts; echo "INFO: Deduced SQL Script filename: '$SCRIPT_SQL'\n" >>$lf

if [ $L = 1 ]; then
  mkdir -p  $l 2>>$lf; rc=$?
  chmod 777 $l 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ALU_LOG/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/ 2>>$lf; ((rc=$rc+$?))
  if [ $rc != 0 ] || [ ! -d $l ]; then pts; echo "ERR: Cannot create/mod log directory: '$l'\n" | tee -a $lf; return 1; fi
fi

if [ $O = 1 ]; then
  mkdir -p  $o 2>>$lf; rc=$?
  chmod 777 $o 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ALU_WORK/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/ 2>>$lf; ((rc=$rc+$?))
  if [ $rc != 0 ] || [ ! -d $o ]; then pts; echo "ERR: Cannot create/mod output directory: '$o'\n" | tee -a $lf; return 1; fi
fi

if [ $I = 1 ]; then
  mkdir -p  $i 2>>$lf; rc=$?
  mkdir -p  $d 2>>$lf; ((rc=$rc+$?))
  chmod 777 $i 2>>$lf; ((rc=$rc+$?))
  chmod 777 $d 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ALU_WORK/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/WORK/ 2>>$lf; ((rc=$rc+$?))
  chmod 777 /workdata/ 2>>$lf; ((rc=$rc+$?))
  if [ $rc != 0 ] || [ ! -d $i ] || [ ! -d $d ]; then pts; echo "ERR: Cannot create/mod input/done directories\n" | tee -a $lf; return 1; fi
fi

if [ $HOST != $DB ]; then
  if [ $L = 1 ]; then
    ssh $DB <<EOF 2>>$lf
      mkdir -p  $l; rc=\$?
      chmod 777 $l; ((rc=\$rc+\$?))
      chmod 777 /workdata/WORK/ALU_LOG/; ((rc=\$rc+\$?))
      chmod 777 /workdata/WORK/; ((rc=\$rc+\$?))
      chmod 777 /workdata/; ((rc=\$rc+\$?))
      if [ \$rc != 0 ] || [ ! -d $l ]; then exit 1; else exit 0; fi
EOF
    if [ $? != 0 ]; then pts; echo "ERR: Cannot create/mod log directory: '$l' on: '$DB'\n" | tee -a $lf; return 1; fi
  fi

  if [ $O = 1 ]; then
    ssh $DB <<EOF 2>>$lf
      mkdir -p  $o; rc=\$?
      chmod 777 $o; ((rc=\$rc+\$?))
      chmod 777 /workdata/WORK/ALU_WORK/; ((rc=\$rc+\$?))
      if [ \$rc != 0 ] || [ ! -d $o ]; then exit 1; else exit 0; fi
EOF
    if [ $? != 0 ]; then pts; echo "ERR: Cannot create/mod output directory: '$o' on: '$DB'\n" | tee -a $lf; return 1; fi
  fi

  if [ $I = 1 ]; then
    ssh $DB <<EOF 2>>$lf
      mkdir -p  $i; rc=\$?
      mkdir -p  $d; ((rc=\$rc+\$?))
      chmod 777 $i; ((rc=\$rc+\$?))
      chmod 777 $d; ((rc=\$rc+\$?))
      chmod 777 /workdata/WORK/ALU_WORK/; ((rc=\$rc+\$?))
      if [ \$rc != 0 ] || [ ! -d $i ]; then exit 1; else exit 0; fi
EOF
    if [ $? != 0 ]; then pts; echo "ERR: Cannot create/mod input/done directories on: '$DB'\n" | tee -a $lf; return 1; fi
    scp -q -r -p $i/* $DB:$i 2>>$lf
    if [ $? != 0 ]; then
      chk=0; tail -1 $lf | grep "No such file or directory" | wc -l | read chk
      if [ $chk = 0 ]; then
        pts; echo "ERR: Cannot copy input files to '$DB:$i'\n" | tee -a $lf; return 1;
      else
        pts; echo "WAR: No input files found in '$i'\n" | tee -a $lf;
      fi
    else
      pts; echo "INFO: Copied input files to '$DB:$i'\n" >>$lf
    fi
  fi
fi

rc=0
pts; echo "Starting SQL script '$SCRIPT_SQL'\n" | tee -a $lf
sqlplus "$CS" @$SCRIPT_SQL $@
if [ $? != 0 ]; then
  pts; echo "\nERR: Error running SQL script '$SCRIPT_SQL'\n" | tee -a $lf; rc=1
else
  pts; echo "\nINFO: SQL script '$SCRIPT_SQL' ran successfully\n" >>$lf
fi

if [ $HOST != $DB ]; then
  if [ $L = 1 ]; then
    scp -q -r -p $DB:$l/* $l 2>>$lf
    if [ $? != 0 ]; then
      chk=0; tail -1 $lf | grep "No such file or directory" | wc -l | read chk
      if [ $chk = 0 ]; then
        pts; echo "ERR: Cannot copy log files from '$DB:$l'\n" | tee -a $lf; return 1;
      else
        pts; echo "WAR: No log files found in '$DB:$l'\n" | tee -a $lf;
      fi
    else
      pts; echo "INFO: Copied log files from '$DB:$l'\n" >>$lf
    fi
    db_delete $l
    if [ $? != 0 ]; then
      pts; echo "WAR: Cannot delete log files from: '$DB:$l'\n" | tee -a $lf;
    else
      pts; echo "INFO: Deleted log files from: '$DB:$l'\n" >>$lf
    fi
  fi

  if [ $O = 1 ]; then
    scp -q -r -p $DB:$o/* $o 2>>$lf
    if [ $? != 0 ]; then
      chk=0; tail -1 $lf | grep "No such file or directory" | wc -l | read chk
      if [ $chk = 0 ]; then
        pts; echo "ERR: Cannot copy output files from '$DB:$o'\n" | tee -a $lf; return 1;
      else
        pts; echo "WAR: No output files found in '$DB:$o'\n" | tee -a $lf;
      fi
    else
      pts; echo "INFO: Copied output files from '$DB:$o'\n" >>$lf
    fi
    db_delete $o
    if [ $? != 0 ]; then
      pts; echo "WAR: Cannot delete output files from: '$DB:$o'\n" | tee -a $lf;
    else
      pts; echo "INFO: Deleted output files from: '$DB:$o'\n" >>$lf
    fi
  fi

  if [ $I = 1 ]; then
    ssh $DB <<EOF 2>>$lf
      rm -rf $i/*
      if [ \$? != 0 ]; then exit 1; else exit 0; fi
EOF
    if [ $? != 0 ]; then
    pts; echo "WAR: Cannot delete input files from: '$DB:$i'\n" | tee -a $lf;
    else
      pts; echo "INFO: Deleted input files from '$DB:$i'\n" >>$lf
    fi
	ls -1 $i/* 2>/dev/null | while read fn; do
      basename $fn | read fn  
	  if [ -f $d/$fn ]; then
        fnn="${fn%.*}"
        fne="${fn##*.}"
		ts=`date +%Y%m%d%H%M%S`
        if [ $fnn = $fne ]; then
          fn2="${fnn}_${ts}"
        else
          fn2="${fnn}_${ts}.${fne}"
        fi
      else
	    fn2=$fn
      fi
      mv $i/$fn $d/$fn2
      if [ $? != 0 ]; then
        pts; echo "WAR: Cannot move input file '$fn' to done directory: '$d'" | tee -a $lf;
      else
        pts; echo "INFO: Moved input file '$fn' to done directory: '$d'" >>$lf
      fi
	done
  fi
fi

return $rc
