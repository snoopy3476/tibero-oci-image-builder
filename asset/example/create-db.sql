-- custom DB creation SQL example

create database "tibero" -- db name should be the same as $TB_SID!
  user sys identified by 'tibero' -- warning: password of sys here should be 'tibero'!
  maxinstances 8
  maxdatafiles 100
  character set UTF8
  national character set UTF8
  logfile
    group 1 'log001-custom.log' size 10M,
    group 2 'log002-custom.log' size 10M,
    group 3 'log003-custom.log' size 10M
  maxloggroups 255
  maxlogmembers 8
  noarchivelog
    datafile 'system001-custom.dtf' size 10M autoextend on next 10M maxsize unlimited
    default temporary tablespace TEMP
      tempfile 'temp001-custom.dtf' size 10M autoextend on next 10M maxsize unlimited
      extent management local autoallocate
    undo tablespace UNDO
      datafile 'undo001-custom.dtf' size 20M autoextend on next 10M maxsize unlimited
      extent management local autoallocate
    SYSSUB
      datafile 'syssub001-custom.dtf' size 10M autoextend on next 10M maxsize unlimited
    default tablespace USR
      datafile 'usr001-custom.dtf' size 10M autoextend on next 10M maxsize unlimited
      extent management local autoallocate;
