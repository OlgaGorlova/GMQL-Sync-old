#!/bin/bash
# Usage: ./gmqlsyncDelHdfsDest.sh <gmqlRepoPath> <hdfsPath> <arrayOfDatasetNames>
# It gets hdfs path to every dataset in the list and removes it in hdfs repository.
# Author: Olga Gorlova
#---------------------------------------------------------

xml=".xml"
hdfs="/usr/local/hadoop/bin/hdfs"

path="$1"
pathHDFS="$2"
shift 2

del=("$@")
for DS in "${del[@]}"
do
    dsHdfsName=($(xpath -q -e /DataSets/dataset/url[@id='0']/text\(\) $path/datasets/$DS$xml | sed -e 's/^\///' | cut -d '/' -f 1))
    if [ $? -ne 0 ]; then
        echo " xpath: could not parse $DS"
        continue
    fi
    test=($($hdfs dfs -test -e $pathHDFS/$dsHdfsName))
    if [ $? -ne 0 ]; then
        echo " hdfs: '$pathHDFS/$dsHdfsName': Path does not exist"
        continue
    else
        deleteFromHdfs=($($hdfs dfs -rm -r $pathHDFS/$dsHdfsName))
        if [ $? -ne 0 ]; then
            echo " hdfs rm: '$pathHDFS/$dsHdfsName': Failed"
            continue
        fi
    fi
done
				
