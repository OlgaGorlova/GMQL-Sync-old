# GMQL-Sync
Script to synchronize GMQL repository between servers

## Usage
```sh
$ ./gmqlsync.sh [<options>] <SOURCE> <DEST>
```
## Description
The script is build for synchronizing gmql repository of public datasets.
It first checks if there are any difference in local FS gmql repository by running 'rsync' tool in dry-run mode.
The result of 'rsync' is then stored in '$rsyncOut' file and parse into two arrays: one is for all the datasets that should be added in \<DEST>, and the other one is for datasets to delete from \<DEST>.

**NOTE:** Dataset names are file names in local FS gmql repository. If tool was run with `--dry-run` option, it will exit after generating datasets list.

After getting the datasets lists, it retrieves hdfs path of every DS, and copy the datasets from hdfs repository to temporary hdfs directory in local FS.
Then, using 'rsync', the files from temporary hdfs dir on \<SOURCE> are copied to temporary hdfs dir on \<DEST>.
After that, on \<DEST>, all files in temporary hdfs directory are copied to hdfs repository on \<DEST>.
Then, compare the dataset sizes in hdfs repositories on both, \<SOURCE> and \<DEST>, to make sure that the copy was successful.
If copying of hdfs files finnished successfully, then copy files in local FS gmql repository by running `rsync` in normal mode.
If the script was run with `--delete` option, then perform removing of datasets on \<DEST>.
Finally, clean up temporary hdfs directories.

The script also generates a .log file in `$scriptLogDir`

Note: The tool consists of several script files to make less ssh connections

The following tools are required on both servers for the correct work of the script:
   - rsync
   - xpath
   - ssh
   - hadoop
