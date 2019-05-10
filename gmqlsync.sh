#!/bin/bash
# Usage: ./gmqlsync.sh [<options>] <SOURCE> <DEST>
#
# The script is build for synchronizing gmql repository of public datasets.
# It first checks if there are any difference in local FS gmql repository by running 'rsync' tool in dry-run mode.
# The result of 'rsync' is then stored in '$rsyncOut' file and parse into two arrays: one is for all the datasets that should be added in <DEST>,
# and the other one is for datasets to delete from <DEST>.
#
# Note: Dataset names are file names in local FS gmql repository. If tool was run with '--dry-run' option, it will exit after generating datasets list.
#
# After getting the datasets lists, it retrieves hdfs path of every DS, and copy the datasets from hdfs repository to temporary hdfs directory in local FS.
# Then, using 'rsync', the files from temporary hdfs dir on <SOURCE> are copied to temporary hdfs dir on <DEST>.
# After that, on <DEST>, all files in temporary hdfs directory are copied to hdfs repository on <DEST>.
# Then, compare the dataset sizes in hdfs repositories on both, <SOURCE> and <DEST>, to make sure that the copy was successful.
# If copying of hdfs files finnished successfully, then copy files in local FS gmql repository by running 'rsync' in normal mode.
# If the script was run with '--delete' option, then perform removing of datasets on <DEST>.
# Finally, clean up temporary hdfs directories.
#
# The script also generates a .log file in '$scriptLogDir'
#
# Note: The tool consists of several script files to make less ssh connections
#
# The following tools are required on both servers for the correct work of the script:
#   - rsync
#   - xpath
#   - ssh
#   - hadoop
#
# Author: Olga Gorlova
#---------------------------------------------------------

##################################################################################
######                       GLOBAL VARIABLES                               ######
##################################################################################

#### The following variable should be set for running the script in crontab
#HOME=/home/gmql
#LOGNAME=gmql
#PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/local/hadoop/bin/:/usr/local/java/bin:/usr/local/hadoop/bin:/usr/local/hadoop/sbin
#LANG=en_US.UTF-8
#SHELL=/bin/bash

scriptPath="/share/repository/gmqlsync/"

#### GMQL user name to sync hdfs data
userName="public"

#### Source path to local FS repository
sourceServer=""
sourcePath="/home/gmql/gmql_repository/data/$userName"
SOURCE="$sourcePath"

#### Destination path to local FS repository
destServer="cineca"
destPath="/gmql-data/gmql_repository/data/$userName"
DEST="$destServer:$destPath"

#### Temporary folder for script output files on local (source) server
tmpFolder="$scriptPath/tmpSYNC"

#### Location of the file containing full rsync dry-run output
rsyncOut="$tmpFolder/rsync_out.txt"
#### Location of file containing datasets that will be added (changed)
rsyncAdd="$tmpFolder/rsync_add.txt"
#### Location of file containing datasets that will be deleted
rsyncDel="$tmpFolder/rsync_del.txt"
#### The file contains hdfs names of changed datasets
HDFS_files="$tmpFolder/ds_hdfs_name.txt"

#### key word for deleted files in rsync output
deleteKeyword="*deleting"

#### arrays for all updated files and distinct names of updated datasets
declare -a updated_files
declare -a distinct_add

#### arrays for all files to delete and distinct names of deleted datasets
declare -a deleted_files
declare -a disctinct_del

#### array of hdfs names of changed datasets
declare -a ds_hdfs_name

#### Temporary folders for hdfs data movement
sourceTmpHDFS="/share/repository/gmqlsync/tmpHDFS"
destTmpHDFS="/hadoop/gmql-sync-temp"

#### Hdfs paths to sync
sourceHDFS="/user/$userName/regions"
destHDFS="/user/$userName/regions"

#### set path to HADOOP_HOME
hdfs="$HADOOP_HOME/bin/hdfs"
hadoop="$HADOOP_HOME/bin/hadoop"

#### Date for logging file name
dateForFileName="$(date +%d%m%Y)"
#### Log dir path
scriptLogDir="$scriptPath/logs/"
appName="gmqlsync"
#### Log file name
scriptLogPath="${scriptLogDir}${appName}-${dateForFileName}.log"
#### Logging Level configuration. The following levels are supported: DEBUG, INFO, WARN and ERROR
scriptLoggingLevel="DEBUG"

#### Other
xml=".xml*"
dry_run=
optionsList=""
optionsShort="-"
inputOptions="h-:"
datePattern="$(date +%d/%m/%Y\ %H:%M:%S)"
excludeOption="--exclude={dag,indexes,logs,queries,results,regions,'.*'}"
excludedDatasets=

##################################################################################
######                       END OF GLOBAL VARIABLES                        ######
##################################################################################



##################################################################################
######                       FUNCTIONS                                      ######
##################################################################################

# LOGGING
# Calls to the logThis() function will determine if an appropriate log file
# exists. If it does, then it will use it, if not, a call to openLog() is made,
# if the log file is created successfully, then it is used.
#
# All log output is comprised of
# [+] A date/time stamp
# [+] The declared level of the log output
# [+] The runtime process ID (PID) of the script
# [+] The log message
openLog()
{
    echo -e "$(date +%d/%m/%Y\ %H:%M:%S) : PID $$ : INFO : New log file (${scriptLogPath}) created." >> "${scriptLogPath}"

    if ! [[ "$?" -eq 0 ]]
    then
        echo "$(date +%d/%m/%Y\ %H:%M:%S) ERROR : UNABLE TO OPEN LOG FILE - EXITING SCRIPT."
        exit 1
    fi
}

logThis()
{
#    dateTime="$(date --rfc-3339=seconds)"

    if [[ -z "${1}" || -z "${2}" ]]
    then
        echo "$(date +%d/%m/%Y\ %H:%M:%S) ERROR : LOGGING REQUIRES A DESTINATION FILE, A MESSAGE AND A PRIORITY, IN THAT ORDER."
        echo "$(date +%d/%m/%Y\ %H:%M:%S) ERROR : INPUTS WERE: ${1} and ${2}."
        exit 1
    fi

    logMessage="${1}"
    logMessagePriority="${2}"

    declare -A logPriorities
    logPriorities[DEBUG]=0
    logPriorities[INFO]=1
    logPriorities[WARN]=2
    logPriorities[ERROR]=3

    [[ ${logPriorities[$logMessagePriority]} ]] || return 1
    (( ${logPriorities[$logMessagePriority]} < ${logPriorities[$scriptLoggingLevel]} )) && return 2


    # No log file, create it.
    if ! [[ -f ${scriptLogPath} ]]
    then
        echo -e "INFO : No log file located, creating new log file (${scriptLogPath})."
        echo "$(date +%d/%m/%Y\ %H:%M:%S) : PID $$ : INFO : No log file located, creating new log file (${scriptLogPath})." >> "${scriptLogPath}"
        openLog
    fi

    # Write log details to file
    echo -e "${logMessagePriority} : ${logMessage}"
    echo -e "$(date +%d/%m/%Y\ %H:%M:%S) : PID $$ : ${logMessagePriority} : ${logMessage}" >> "${scriptLogPath}"
}
#################################################################################
#                        ##      END OF LOGGING     ##
#################################################################################


#### Show defaults parameters
defaults()
{
    echo ""
    echo "Defaults:"
    echo "  SOURCE=$SOURCE"
    echo "  DEST=$DEST"
    echo "  USER=$userName"
    echo "  tmpDir=$tmpFolder"
    echo "  tmpHdfsSource=$sourceTmpHDFS"
    echo "  tmpHdfsDest=$destTmpHDFS"
    echo ""
}

#### Show usage
usage()
{
    echo ""
    echo "Usage: ./gmqlsync.sh [<options>] <SOURCE> <DEST>"
    echo ""
    echo "gmqlsync.sh MUST be run on <SOURCE> server"

    defaults

    echo "Options:"
    echo "  --delete                delete extraneous files from destination dirs"
    echo "  --dry-run               perform a trial run with no changes made,"
    echo "                          this also generates a list of changed datasets"
    echo "  --user                  set user name (hdfs folder name) to synchronize"
    echo "  --tmpDir                set temporary directory for local script output files"
    echo "  --tmpHdfsSource         set temporary directory for hdfs files movement on source server"
    echo "  --tmpHdfsDest           set temporary directory for hdfs files movement on destination server"
    echo "  --logsDir               logging directory on source server"
    echo "  --help, (-h)            show this help"
    echo ""

}

#### Set SOURCE and DEST variables from input
set_source_and_dest()
{
    if [ "$#" -ne 0 ]; then
        if [[ "$1" == *":"* ]]; then
            sourcePath=($(echo "$1" | cut -d ':' -f 2))
            sourceServer=($(echo "$1" | cut -d ':' -f 1))
        else
            sourcePath="$1"
            sourceServer=""
        fi
            SOURCE="$1"

        if [[ "$2" == *":"* ]]; then
            destPath=($(echo "$2" | cut -d ':' -f 2))
            destServer=($(echo "$2" | cut -d ':' -f 1))
        else
            destPath="$2"
            destServer=""
        fi
            DEST="$2"
    fi
}

#### Parse input parameters
parse_input()
{
    if [ "$#" = 0 ]; then
        defaults
    else
        while getopts "$inputOptions" OPTION; do
            case "$OPTION" in
                h) usage; exit;;
                -) case "${OPTARG}" in
                        dry-run)
                            dry_run=1
                            logThis "DRY RUN is on" INFO
                            ;;
                        delete)
                            optionsList="${optionsList} --delete "
                            logThis "Extraneous files will be deleted from destination server" INFO
                            ;;
                        user=*) val=${OPTARG#*=}
                            userName="$val"
                            sourceHDFS="/user/$userName/regions"
                            destHDFS="/user/$userName/regions"
                            logThis "User name is set to: '${userName}'" INFO
                            ;;
                        tmpDir=*) val=${OPTARG#*=}
                            tmpFolder="$val"
                            rsyncOut="$tmpFolder/rsync_out.txt"
                            rsyncAdd="$tmpFolder/rsync_add.txt"
                            rsyncDel="$tmpFolder/rsync_del.txt"
                            HDFS_files="$tmpFolder/ds_hdfs_name.txt"
                            logThis "Temporary folder is set to: '${tmpFolder}'" INFO
                            ;;
                        tmpHdfsSource=*) val=${OPTARG#*=}
                            sourceTmpHDFS="$val"
                            logThis "Temporary HDFS folder on SOURCE is set to: '${sourceTmpHDFS}'" INFO
                            ;;
                        tmpHdfsDest=*) val=${OPTARG#*=}
                            destTmpHDFS="$val"
                            logThis "Temporary HDFS folder on DESTINATION is set to: '${destTmpHDFS}'" INFO
                            ;;
                        hdfs=*) val=${OPTARG#*=}
                            hdfs="$val"
                            logThis "HADOOP_HOME/bin/hdfs is set to: '${hdfs}'" INFO
                            ;;
                        logsDir=*) val=${OPTARG#*=}
                            scriptLogDir="$val"
                            scriptLogPath="${scriptLogDir}${appName}-${dateForFileName}.log"
                            logThis "Logging directory is set to: '${scriptLogDir}'" INFO
                            ;;
                        logLevel=*) val=${OPTARG#*=}
                            scriptLoggingLevel="$val"
                            logThis "Logging level is set to: '${scriptLoggingLevel}'" INFO
                            ;;
                        exclude=*) val=${OPTARG#*=}
                            excludedDatasets="$excludedDatasets,$val"
                            logThis "The following will be excluded from copiyng: '$val'" INFO
                            ;;
                        help) usage; exit ;;
                        *)  if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                                logThis "Unknown option --${OPTARG}" WARN
                            fi
                            ;;
                    esac;;
                ?) usage; exit 1;;
                *) usage; exit 1;;

                esac
            done
        shift "$(($OPTIND -1))"

        if [ "$#" -gt 2 ] || [ "$#" -eq 1 ]; then
            logThis "Illegal number of parameters" WARN
            usage; exit 1;
        else
            set_source_and_dest "$@"
        fi
    fi
}

#### Check if command exited with error code, and prints msg
check_command_output()
{
    if [ $? -ne 0 ];then
        logThis "$1" ERROR && exit 1
    else
        if [ -n "$2" ]; then
            logThis "$2" INFO
        fi
    fi
}

#### Clean up temporary hdfs folders
clean_tmp_hdfs()
{
    logThis "Removing temporary HDFS directories ... " INFO
    ### Clean $sourceTmpHDFS folder
    removeSourceTmp="$(rm -r $sourceTmpHDFS/*)"
    if [ $? -ne 0 ];then
        logThis "An error occured during removing files under $sourceTmpHDFS folder!" WARN
    else
        logThis "Deleted $sourceTmpHDFS/" INFO
    fi
    ### Clean $destTmpHDFS folder
    removeDestTmp=($(ssh $destServer "rm -r $destTmpHDFS/*"))
    if [ $? -ne 0 ];then
        logThis "An error occured during removing files under $destTmpHDFS folder!" WARN
    else
        logThis "Deleted $destTmpHDFS/" INFO
    fi
}

#### Check if destination server has enough space
check_free_space()
{
    spaceSource="$(du -s $sourceTmpHDFS | cut -f1)"
    spaceDest=($(ssh $destServer "df $destTmpHDFS" | awk 'NR==2 {print $4}'))
    spaceSourceHumanReadable="$(du -sh $sourceTmpHDFS | cut -f1)"
    spaceDestHumanReadable=($(ssh $destServer "df -h $destTmpHDFS" | awk 'NR==2 {print $4}'))
    if [ "$spaceDest" -lt "$spaceSource" ]; then
        logThis "Not enough space on destination server ('$destServer'). Required: $spaceSourceHumanReadable, free: $spaceDestHumanReadable" WARN
#        exit 1
    fi
}

#### Ckeck if temporary folder is not empty at the beggining, if not then clean it
tmpDir_Is_Empty()
{
    if [ -n "$(ls $tmpFolder)" ]; then
#        echo "$datePattern WARN : Temporary folder $tmpFolder is not empty. Cleaning before start ..."
        logThis "Temporary folder ('$tmpFolder') is not empty. Cleaning before start ..." WARN
        removeSourceTmp="$(rm -r $tmpFolder/*)"
        if [ $? -ne 0 ];then
#            echo "$datePattern WARN : An error occured during removing files under $tmpFolder folder!"
            logThis "An error occured during cleaning temporary folder ('$tmpFolder')." WARN
        fi
    fi
}

##################################################################################
######                       END OF FUNCTIONS                               ######
##################################################################################



##################################################################################
######                       MAIN                                           ######
##################################################################################

logThis "STARTING $appName" INFO

#### Parse input options
parse_input "$@"

#### Check if $tmpFolder is empty
tmpDir_Is_Empty

#### Trim spaces arround $optionsList
optionsList=($(echo "$optionsList" | awk '{gsub(/^ +| +$/,"")} {print $0}'))
excludeOption="--exclude={dag,indexes,logs,queries,results,regions,'.*',${excludedDatasets#","}}"
#### Rsync command dry-run
logThis "Rsync dry-run is executing..." INFO
rsyncDryRun="$(rsync -avzh $excludeOption --ignore-existing --itemize-changes $optionsList --dry-run $SOURCE/ $DEST/)"
check_command_output "An error occured during rsync dry-run command execution!"
logThis "Rsync dry-run has finished" INFO

#### Save the output of dry-run with the list of changed items into $rsync_out
echo "$rsyncDryRun" > "$rsyncOut"

#### If file exists
if [[ -f "$rsyncOut" ]]
then
    #### Parse rsync dry-run output to get lists of datasets to update and/or delete
    logThis "Parsing rsync output..." INFO
    while IFS== read -r line ;do
        ## if line starts with "<f" or ">f" (file was updated)
        if [[ "${line:0:2}" == *"<f"* || "${line:0:2}" == *">f"* ]]
        then
            updated_files+=($(echo ${line} | sed 's/[^ ]* //' | awk -F/ '{print $NF}' | cut -d '.' -f 1))
        fi
        ## if line contains "*deleting" (file was deleted)
        if [[ "${line:0:${#deleteKeyword}}" == *"$deleteKeyword"* ]]
        then
            deleted_files+=($(echo ${line} | sed 's/[^ ]* //' | awk -F/ '{print $NF}' | cut -d '.' -f 1))
        fi
    done <"$rsyncOut"

    #### Prepape list of distinct DS names
    if [ -z "$updated_files" ] && [ -z "$deleted_files" ]; then
        logThis "No files have been modified" INFO && exit 0
    else
        if [ -n "$updated_files" ]; then
            distinct_add=($(echo "${updated_files[@]}" | tr ' ' '\n' | sed -e 's/^[ \t]*//' | sort -u | tr '\n' ' ' ))
            printf "%s\n" "${distinct_add[@]}" > "$rsyncAdd"
            logThis "List of datasets to update is saved to: '$rsyncAdd'" INFO
        fi
        if [ -n "$deleted_files" ]
        then
            distinct_del=($(echo "${deleted_files[@]}"  | tr ' ' '\n' | sort -u | tr '\n' ' ' ))
            printf "%s\n" "${distinct_del[@]}" >"$rsyncDel"
            logThis "List of datasets to delete is saved to: '$rsyncDel'" INFO
        fi
    fi
    logThis "Rsync output was parsed" INFO

    #### If dry-run is ON then exit
    if [ "$dry_run" = "1" ]; then
        logThis "The script was run in --dry-run mode, the output is saved to: '$rsyncOut'" INFO
        logThis "Bye-Bye!" INFO
        exit
    fi

    #### Get HDFS names of updated datasets on SOURCE server (local)
    logThis "Getting HDFS names..." INFO
    for DS in "${distinct_add[@]}"
    do
        ds_hdfs_name+=($(xpath -q -e /DataSets/dataset/url[@id='0']/text\(\) $sourcePath/datasets/$DS$xml | sed -e 's/^\///' | cut -d '/' -f 1))
        if [ $? -ne 0 ];then
            logThis "Something went wrong while retrieving '$DS' dataset name in HDFS" WARN
        fi
    done


    if [ -n "$ds_hdfs_name" ]
    then
        #### Save list of hdfs names to $HDFS_files
        printf "%s\n" "${ds_hdfs_name[@]}" > "$HDFS_files"

        #### Copy DS from HDFS to local FS on SOURCE server (local)
        logThis "Copying datasets from HDFS to temporary directory ('$sourceTmpHDFS') ..." INFO
        for DS in "${ds_hdfs_name[@]}"
        do
            if [ -d $sourceTmpHDFS/$DS ]; then
                logThis "Skipping dir '$sourceTmpHDFS/$DS'. Path already exists" WARN
            else
#                copyToLocal=($(hdfs dfs -get $sourceHDFS/$DS $sourceTmpHDFS))
                copyToLocal=($(hadoop distcp $sourceHDFS/$DS file://$sourceTmpHDFS))
                check_command_output "An error occured during copying '$DS' dataset from hdfs to local." "'$DS' is copied from HDFS to temporary directory ('$sourceTmpHDFS')."
            fi
        done
        logThis "HDFS files were copied to temporary directory ($sourceTmpHDFS)" INFO

        #### Check if destination server has enough space
        check_free_space

        #### Copy hdfs data from <SOURCE> to <DEST> using rsync
        #### Note: $destTmpHDFS should be empty
        logThis "Copying data from source temporary directory ('$sourceServer:$sourceTmpHDFS') to destination temporary directory ('$destServer:$destTmpHDFS') ..." INFO
#        moveFromSourceToDest="$(rsync -avzh --exclude={GRCh38_TCGA_methylation_2018_12_20181219_212149,GRCh38_ENCODE_NARROW_2018_12_20181217_130749,HG19_ENCODE_NARROW_2018_12_20181217_114532} --itemize-changes $sourceTmpHDFS/ $destServer:$destTmpHDFS/)"
        moveFromSourceToDest="$(rsync -avzh --itemize-changes $sourceTmpHDFS/ $destServer:$destTmpHDFS/)"
        check_command_output "An error occured during transfering files from '$sourceTmpHDFS' to '$destTmpHDFS!'" "Data from '$sourceServer:$sourceTmpHDFS' was copied to '$destServer:$destTmpHDFS'"

        #### Copy from local $destTmpHDFS to HDFS on DEST server (remote)
        logThis "Copying data from temporary directory ('$destServer:$destTmpHDFS') to HDFS ..." INFO
#        copyToHdfs=($(ssh -o "ServerAliveInterval 120" -o "ServerAliveCountMax 720" $destServer "$hdfs dfs -copyFromLocal -f $destTmpHDFS/* $destHDFS" 2>&1))
        copyToHdfs=($(ssh -o "ServerAliveInterval 120" -o "ServerAliveCountMax 720" $destServer "$hadoop distcp file://$destTmpHDFS/* $destHDFS" 2>&1))
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            logThis "An error occured during copying datasets from local to hdfs." ERROR
            err_msg="network error: \n""$copyToHdfs"
            logThis "$err_msg" ERROR
            exit 1
        fi
        check_command_output "An error occured during copying datasets from temporary directory ('$destServer:$destTmpHDFS') to hdfs." "Data from temporary directory ('$destServer:$destTmpHDFS') was copied to HDFS"

        #### Check if sizes in HDFS are equal on both servers
        logThis "Comparing data sizes in hdfs on <SOURCE> and <DEST> ..." INFO
        check=0
        checkHdfsDest=($(ssh "$destServer" 'bash -s' < $scriptPath/gmqlsyncCheckHdfsDest.sh "$destHDFS" "${ds_hdfs_name[@]}" 2>&1))
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            logThis "Something went wrong during getting data sizes in hdfs on destionation server!" ERROR
            err_msg="network error: \n""$checkHdfsDest"
            logThis "$err_msg" ERROR
            exit 1
        fi
        check_command_output "Something went wrong during getting data sizes in hdfs on destionation server!"

        while IFS=';' read -ra DSS; do
            for i in "${DSS[@]}"; do
                if [ -n "$i" ]; then
                    key=($(echo "$i" | cut -d "=" -f 1))
                    val=($(echo "$i" | cut -d "=" -f 2))
                    sourceVal=($(hdfs dfs -du -s $sourceHDFS/$key | cut -d ' ' -f 1))
                    if [ "$sourceVal" -ne "$val" ]; then
                        check=1
                    fi
                fi
            done
        done <<< "$checkHdfsDest"

        if [[ "$check" -eq 1 ]]; then
            logThis "Something went wrong during copying hdfs data - data sizes do not match" WARN
            logThis "Cleaninig temporary HDFS directories..." WARN
            ### Clean temporary hdfs folders
            clean_tmp_hdfs
        fi

    else
        logThis "ds_hdfs_name is empty" WARN
    fi

    #### Delete datasets in HDFS first (if any)
    if [[ -f "$rsyncDel" ]] && [ -n "$distinct_del" ]
    then
        logThis "Deleting datasets in HDFS ... " INFO
        hdfsDelRemote=($(ssh "$destServer" 'bash -s' < $scriptPath/gmqlsyncDelHdfsDest.sh "$destPath" "$destHDFS" "${distinct_del[@]}" 2>&1))
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            logThis "Something went wrong during deleting datasets in hdfs on destionation server! " ERROR
            err_msg="network error: \n""$hdfsDelRemote"
            logThis "$err_msg" ERROR
            exit 1
        else
            echo "$hdfsDelRemote"
        fi

#        logThis "$hdfsDelRemote" DEBUG
#        check_command_output "Something went wrong during deleting datasets in hdfs on destionation server! "
    fi

    #### Synchronize local gmql repository using 'rsync'
    logThis "Executing rsync for syncing local FS ..." INFO
rsync_run="$(rsync -avzh --exclude={${excludedDatasets#","}} --ignore-existing --itemize-changes $optionsList $SOURCE/ $DEST/)"
    check_command_output "An error occured during rsync command execution!"

    ### Clean temporary hdfs folders
    clean_tmp_hdfs

    logThis "Synchronization has finished successfully!" INFO
    exit
fi
