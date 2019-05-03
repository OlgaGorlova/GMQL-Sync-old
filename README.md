# GMQL-Sync
The script is designed for synchronizing GMQL public repository between two servers

## Requirements
The following tools are required to be installed on both servers for the correct work of the script:
   - Apache Hadoop.
      - Guide for Apache Hadoop installation can be found in [Hadoop installation page](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SingleCluster.html).
   - Make sure that `rsync`, `ssh` and `xpath` are installed.
      - You can use this command in terminal (Ubuntu/Debian) to install them:
          ```sh
         $ sudo apt-get install rsync
         $ sudo apt-get install libxml-xpath-perl
         $ sudo apt-get install ssh
         ```
## Usage
```sh
$ ./gmqlsync.sh [<options>] <SOURCE> <DEST>
```
`gmqlsync.sh` **MUST BE** run on `<SOURCE>` server
   
### Defaults
It can also be used with no parameters:
   ```sh 
   $ ./gmqlsync.sh
   ```
In that case, the `<SOURCE>` and `<DEST>` are set to the following:
  - `<SOURCE>`=/home/gmql/gmql_repository/data/public
  - `<DEST>`=cineca:/gmql-data/gmql_repository/data/public

### Options
| Option            | Description |
|-------------------|-------------|
|  `--delete`       | delete extraneous files from destination dirs|
|  `--dry-run`      | perform a trial run with no changes made, this only generates a list of changed datasets|
|  `--user`         | set user name (hdfs folder name) to synchronize|
|  `--tmpDir`       | set temporary directory for local script output files. Default value is: <br/> `"/share/repository/gmqlsync/tmpSYNC"`|
|  `--tmpHdfsSource`| set temporary directory for hdfs files movement on source server. Default value is: <br/> `"/share/repository/gmqlsync/tmpHDFS"`|
|  `--tmpHdfsDest`  | set temporary directory for hdfs files movement on destination server. Default value is: <br/> `"/hadoop/gmql-sync-temp"`|
|  `--logsDir`      | logging directory on source server. Default value is  `"/share/repository/gmqlsync/logs/"`|
|  `--help, (-h)`   | show help|

### Examples

1. To synchronize cineca server with genomic, run the following command:
```sh
$ ./gmqlsync.sh /home/gmql/gmql_repository/data/public cineca:/gmql-data/gmql_repository/data/public
```
2. To get a list of datasets that exists on genomic server, but are missed on cineca server, run the following:
```sh
$ ./gmqlsync.sh --dry-run /home/gmql/gmql_repository/data/public cineca:/gmql-data/gmql_repository/data/public
```
   With `--dry-run` option, the script only checks for differences on the serves, and generates a file with a list of new     datasets.

3. To allow deletion of datasets that we removed from genomic server, use the following command:
```sh
$ ./gmqlsync.sh --delete /home/gmql/gmql_repository/data/public cineca:/gmql-data/gmql_repository/data/public
```

## Description
The script is build for synchronizing gmql repository of public datasets.
It first checks if there are any difference in local FS GMQL repository by running `rsync` tool in dry-run mode.
The result of `rsync` is then stored in `rsync_out.txt` file and parse into two arrays: one is for all the datasets that should be added in `<DEST>`, and the other one is for datasets to delete from `<DEST>`. Datasets list to add and delete are then saved to `rsync_add.txt` and `rsync_del.txt` files respectivelly.

**NOTE:** Dataset names are file names in local FS GMQL repository. If tool was run with `--dry-run` option, it will exit after generating datasets list.

After getting the datasets lists, it retrieves hdfs path of every DS, and copy the datasets from hdfs repository to temporary hdfs directory in local FS.
Then, using `rsync`, the files from temporary hdfs dir on `<SOURCE>` are copied to temporary hdfs dir on `<DEST>`.
After that, on `<DEST>`, all files in temporary hdfs directory are copied to hdfs repository on `<DEST>`.
Then, compare the dataset sizes in hdfs repositories on both, `<SOURCE>` and `<DEST>`, to make sure that the copy was successful.
If copying of hdfs files finnished successfully, then copy files in local FS gmql repository by running `rsync` in normal mode.
If the script was run with `--delete` option, then perform removing of datasets on `<DEST>`.
Finally, clean up temporary hdfs directories.

The script also generates a `.log` file in `logs` folder.

## Script files
The tool consists of several script files to make less ssh connections:
- `gmqlsync.sh` is the main script file to be used
- `gmqlsyncCheckHdfsDest.sh` gets dataset size in hdfs on the destination server
- `gmqlsyncDelHdfsDest.sh` removes datasets on the destination server

**NOTE:** `ssh` connection to the remote server should be passwordless.

# Backup script
The script is designed for backing up GMQL public repository after the synchronization. 

## Description
The script performs the backup of the datasets from a given list to a given destination server. It simply downloads the datasets from genomic server using REST API. If `--full` option is used, then it firts takes the list of all datasets in genomic repository and then downloads all of them to destination server.

## Usage
```sh
$ ./backupDS.sh [<options>] <FILENAME> <DEST>
```
`<DEST>` should be in the following format: `<server>:<path>`

### Options
| Option            | Description |
|-------------------|-------------|
|  `--full`         | do the full GMQL repository backup|
|  `--help, (-h)`   | show help|

### Examples

1. After running the synchronization, you can find the datasets that were added in the following file:
`"/share/repository/gmqlsync/tmpSYNC/rsync_add.txt"`
You can use this file to backup the newly added datasets:
```sh
$ ./backupDS.sh /share/repository/gmqlsync/tmpSYNC/rsync_add.txt geco:/home/hdfs/gmql_repo_backup/
```
2. If you want to do the backup of full GMQL public repository, then you can use `--full` option. In this case, you do not need to provide the file with dataset list:
```sh
$ ./backupDS.sh --full geco:/home/hdfs/gmql_repo_backup/
```

