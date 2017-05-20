L=1 #If the scripts needs log folder set to 1 otherwise 0
O=1 #If the scripts needs output folder set to 1 otherwise 0
I=1 #If the scripts needs input/done folders set to 1 otherwise 0

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

l="/workdata/WORK/ALU_LOG/$SCRIPT_DIR/"
o="/workdata/WORK/ALU_WORK/$SCRIPT_DIR/OUTPUT/"
i="/workdata/WORK/ALU_WORK/$SCRIPT_DIR/INPUT/"
d="/workdata/WORK/ALU_WORK/$SCRIPT_DIR/DONE/"

DB=`$HOME/ALU_BIN/GENERIC/get_db_name.sh $BSCSDB 2>>$lf` 2>>$lf
if [ $? != 0 ] || [ "D$DB" = "D" ]; then pts; echo "ERR: Cannot get databse host name\n" | tee -a $lf; return 1; fi
pts; echo "INFO: Database host name: '$DB'\n" >>$lf

HOST=`hostname 2>>$lf` 2>>$lf
if [ $? != 0 ] || [ "H$HOST" = "H" ]; then pts; echo "ERR: Cannot get current host name\n" | tee -a $lf; return 1; fi
pts; echo "INFO: Current host name: '$HOST'\n" >>$lf

if [ $L = 1 ]; then pts; echo "INFO: Script has log\n" >>$lf; fi
if [ $O = 1 ]; then pts; echo "INFO: Script has output\n" >>$lf; fi
if [ $I = 1 ]; then pts; echo "INFO: Script has input\n" >>$lf; fi

sqlplus -s sysadm/sysadm@$BSCSDB <<EOF | read VER
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
sqlplus sysadm/sysadm@$BSCSDB @$SCRIPT_SQL $@
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
