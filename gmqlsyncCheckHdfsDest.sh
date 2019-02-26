#!/bin/bash
# Usage: ./gmqlsyncCheckHdfsDest.sh <hdfsPath> <arrayOfDatasetsNames>
# The script gets dataset size in hdfs and return an assocciative array of 'dsName=size'
# Author: Olga Gorlova
#---------------------------------------------------------

hdfs="/usr/local/hadoop/bin/hdfs"

destHDFS="$1"
shift

del=("$@")
				
for DS in "${del[@]}"
do
    checkHDFSDest=($($hdfs dfs -du -s $destHDFS/$DS | cut -d ' ' -f 1))
    if [ $? -ne 0 ]; then
        exit 1
    fi
    echo "$DS=$checkHDFSDest;"
done
