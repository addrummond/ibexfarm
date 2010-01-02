#!/bin/sh
script/ibexfarm_create.pl model DB DBIC::Schema IbexFarm::Schema create=static components=TimeStamp,EncodedColumn 'dbi:Pg:dbname=ibexfarm;host=localhost;port=5432' lfuser abcd '{ AutoCommit => 0}'

