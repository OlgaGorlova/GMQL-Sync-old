#!/bin/bash
# Usage: ./backupDS 'filename' 'destPath'
#
# Do the backup of the datasets from a given list to a given destination server.
# It simply downloads the datasets from genomic server using REST API.
# If 'full' flag is used, then it firts takes the list of all datasets in genomic
# repository and then downloads all of them to destination server.
#
# Author: Olga Gorlova
#---------------------------------------------------------

filePath="$1"
backupPath="$2"
backupServer=
BACKUP=

fullDSlist="fullDSlist.txt"
full=0

zip=".zip"

optionsList=""
optionsShort="-"
inputOptions="hf-:"

#### Show usage
usage()
{
    echo ""
    echo "Usage: ./backupDS.sh [<options>] <FILENAME.txt> <DEST>"
    echo ""
    echo "<DEST> should be in the format of <servername>:<path>"
    echo ""

    echo "Options:"
    echo "  --full                  do the full repository backup"
    echo "  --help, (-h)            show this help"
    echo ""

}

#### Set SOURCE and DEST variables from input
set_backup_server()
{
    if [ "$#" -ne 0 ]; then
        if [[ "$1" == *":"* ]]; then
            backupPath=($(echo "$1" | cut -d ':' -f 2))
            backupServer=($(echo "$1" | cut -d ':' -f 1))
        else
            backupPath="$1"
            backupServer=""
        fi

        BACKUP="$1"
    fi
}

#### Parse input parameters
parse_input()
{
    if [ "$#" = 0 ]; then
       echo "Illegal number of parameters" && exit 1
    else
        while getopts "$inputOptions" OPTION; do
            case "$OPTION" in
                h) usage; exit;;
                f) full=1;;
                -) case "${OPTARG}" in
                    full)
                        full=1
                        ;;
                    help) usage; exit ;;
                    *)  if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                            echo "Unknown option --${OPTARG}"
                        fi
                        ;;
                    esac;;
                ?) usage; exit 1;;
                *) usage; exit 1;;
            esac
        done

        shift "$(($OPTIND -1))"

        if [ "$#" -eq 0 ] || [ "$#" -lt 2 ]; then
            echo "Illegal number of parameters"
            usage; exit 1;
        else
            filePath="$1"
            if [[ "$2" == *":"* ]]; then
                backupPath=($(echo "$2" | cut -d ':' -f 2))
                backupServer=($(echo "$2" | cut -d ':' -f 1))
            else
                backupPath="$1"
                backupServer=""
            fi
        fi
    fi
}


parse_input "$@"

if [[ "$full" -eq 0 ]]
then
    echo "full backup is OFF"
    if [[ -f "$filePath" ]]
    then
        while IFS= read -r ds
        do
            getDS=($(ssh -o "ServerAliveInterval 120" -o "ServerAliveCountMax 720" $backupServer "wget -q --output-document $backupPath/$ds$zip http://genomic.elet.polimi.it/gmql-rest/datasets/public.$ds/zip?authToken=DOWNLOAD-TOKEN" < /dev/null))
            if [ $? -ne 0 ];then
                echo "Something went wrong when downloading $ds"
            else
                echo "$ds was successfully dowloaded to $backupServer:$backupPath"
            fi
        done < "$filePath"
    fi
else
    echo "full backup is ON"
    datasets="$(wget -O - http://genomic.elet.polimi.it/gmql-rest/datasets?authToken=DOWNLOAD-TOKEN | xpath -q -e /datasets/dataset/name/text\(\) >> $fullDSlist)"
    if [[ -f "$fullDSlist" ]]
    then
        while IFS= read -r ds
        do
            getDS=($(ssh -o "ServerAliveInterval 120" -o "ServerAliveCountMax 720" $backupServer "wget -q --output-document $backupPath/$ds$zip http://genomic.elet.polimi.it/gmql-rest/datasets/public.$ds/zip?authToken=DOWNLOAD-TOKEN" < /dev/null))
            if [ $? -ne 0 ];then
                echo "Something went wrong when downloading $ds"
            else
                echo "$ds was successfully dowloaded to $backupServer:$backupPath"
            fi
        done < "$fullDSlist"
    fi

    rm="$(rm $fullDSlist)"
fi

