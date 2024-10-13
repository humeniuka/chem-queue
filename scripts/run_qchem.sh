#!/bin/bash
#
# To submit a Q-Chem input file `water.in` to 4 processors
# using 10Gb of memory run
#
#   run_qchem.sh  water.in  4   10Gb
#
#

show_help() {
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  qchem.in  nproc  mem"
    echo " "
    echo "    submits Q-Chem script qchem.in for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "  Example:  $(basename $0)  qchem.in 16  40Gb"
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
err=$(dirname $job)/$(basename $job .in).err
# name of the job which is shown in the queueing table
name=$(basename $job .in)
# number of processors (defaults to 1)
nproc=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6Gb}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

echo "submitting '$job' (using $nproc processors and $mem of memory)"

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.
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
module load qchem

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/tmp}
jobdir=\$tmpdir/\${PBS_JOBID}

# scratch folder on compute node
export QCSCRATCH=\${jobdir}
export QCTMPDIR=\${jobdir}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # move checkpoint files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

in=$job
out=\$(dirname \$in)/\$(basename \$in .in).out

# The QChem job might depend on other files specified with READ keyword.
# These files have to be copied to the scratch folder to make them 
# available to the script.
for f in \$(grep -i "READ" \$in | sed 's/READ//gi')
do
   echo "job needs file '\$f' => copy it to scratch folder"
   if [ -f \$f ]
   then
      cp \$f \$jobdir
   else
      echo "\$f not found"
   fi
done

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to \$out (in the global filesystem).

cd \$jobdir

echo "Running QChem ..."
qchem -nt ${nproc} \$in \$out > qchem_env_settings

# Did the job finish successfully ?
success=\$(tail -n 20 \$out | grep "Thank you very much for using Q-Chem.")
if [ "\$success" ]
then
   echo "QChem job finished normally."
   ret=0
else
   echo "QChem job failed, see \$out."
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

# Pass return value of QChem job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
