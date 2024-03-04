#!/bin/bash
#
# To submit a Gaussian input file `molecule.gjf` to 4 processors
# using 10G of memory run
#
#   run_gaussian.sh  molecule.gjf  4   10G
#

show_help() {
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.gjf  nproc  mem"
    echo " "
    echo "    submits Gaussian script molecule.gjf for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The Gaussian log-file is written to molecule.log in the same folder,"
    echo "    whereas the checkpoint files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "    In the Gaussian script '%Nproc=...' should be omitted, but the amount of memory still has"
    echo "    to be specified via '%Mem=...'' ."
    echo " "
    echo "  Example:  $(basename $0)  molecule.gjf 16  40G"
    echo " "
    exit 1
}

# All options are passed to qsub
options=""
for var in "$@"
do
    if [ "$(echo $var | grep "^-")" != "" ]
    then
	options="$options $var"
    fi
done

if [ ! -f "$1" ]
then
    show_help
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .gjf).err
# name of the job which is shown in the queueing table
name=$(basename $job .gjf)
# number of cores (defaults to 1)
nproc=${2:-1}
# memory (defaults to 2G)
mem=${3:-2G}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

echo "submitting '$job' (using $nproc cores and $mem of memory)"

# submit to PBS queue
qsub $options <<EOF
#!/bin/bash

# ===== PBS options ======
# Specify job queue (partition)
#PBS -q SMALL
# Time limit of 12 hours
#PBS -l walltime=12:00:00
# Request resources
#PBS -l select=1:ncpus=${nproc}:mem=${mem}
# Jobname
#PBS -N ${name}
# Output and errors
#PBS -j eo
#PBS -e ${err}
#PBS -o ${err}
# ==========================

echo "----- PBS environment variables ------------------------------------------------------"
echo "Number of threads, defaulting to number of CPUs: \$NCPUS"
echo "The job identifier assigned to the job: \$PBS_JOBID"
echo "The name of the queue from which the job is executed: \$PBS_QUEUE"
echo "The job-specific temporary directory for this job: \$TMPDIR"
echo "The absolute path of directory where qsub was executed: \$PBS_O_WORKDIR"
echo "--------------------------------------------------------------------------------------"

DATE=\$(date)
echo ------------------------------------------------------
echo Start date: \$DATE
echo ------------------------------------------------------

# Sometimes the module command is not available, load it.
source /etc/profile.d/modules.sh

# Here required modules are loaded and environment variables are set
module load g16

# Input and log-file are not copied to the scratch directory.
in=${job}
log=\$(dirname \$in)/\$(basename \$in .gjf).log

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/tmp}
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # remove temporary Gaussian files
    rm -f \$jobdir/Gau-*
    # copy checkpoint files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# The Gaussian job might depend on old checkpoint files specified 
# with the %OldChk=... option. These checkpoint files have to be
# copied to the scratch folder to make them available to the script.
for oldchk in \$(grep -i "%oldchk" \$in | sed 's/%oldchk=//gi')
do
   echo "job needs old checkpoint file '\$oldchk' => copy it to scratch folder"
   if [ -f \$oldchk ]
   then
      cp \$oldchk \$jobdir
   else
      echo "\$oldchk not found"
   fi
done

# Copy external @-files (geometries, basis sets) to the scratch folder
for atfile in \$(grep -i "^@" \$in | sed 's/@//gi')
do
   echo "job needs external file '\$atfile' => copy it to scratch folder"
   if [ -f \$atfile ]
   then
      cp \$atfile \$jobdir
   else
      echo "\$atfile not found"
   fi
done

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to $log (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running Gaussian ..."
g16 -p=${nproc} < \$in &> \$log

# Did the job finish successfully ?
success=\$(tail -n 1 \$log | grep "Normal termination of Gaussian")
if [ "\$success" ]
then
   echo "Gaussian job finished normally."
   ret=0
else
   echo "Gaussian job failed, see \$log."
   ret=1
fi

# The results are copied back to the server
# and the scratch directory is cleaned.
echo "Copying results back ..."

clean_up

DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

# Pass return value of Gaussian job on to the PBS queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'qsub --wait ...' is the output of the batch script, i.e. $ret.
exit $?
