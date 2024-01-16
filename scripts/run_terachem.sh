#!/bin/bash
#
# To submit a TeraChem input file `molecule.inp` to 2 GPUs
# using 6Gb of memory per GPU run
#
#   run_terachem.sh  molecule.inp   2   6G
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.inp  ngpu  mem"
    echo " "
    echo "    submits TeraChem input molecule.inp for calculation with 'ngpu' GPUs"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The TeraChem log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.inp  2  6G"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .inp).err
# name of the job which is shown in the queueing table
name=$(basename $job .inp)
# number of processors (defaults to 1)
ngpu=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6G}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

# All options (arguments starting with --) are extracted from the command
# line and are passed on to sbatch.
options=""
for var in "$@"
do
    if [ "$(echo $var | grep "^--")" != "" ]
    then
	options="$options $var"
    fi
done

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

>&2 echo "submitting '$job' (using $ngpu GPUs and $mem of memory)"

# submit to SLURM queue
sbatch $options <<EOF
#!/bin/bash

# ===== SLURM options ======
# Specify job queue (partition)
#SBATCH -p ${SBATCH_PARTITION:-gr10564g}
# Time limit of 2 days
#SBATCH -t 2-0:0:0
# Request resources
# see https://web.kudpc.kyoto-u.ac.jp/manual/en/run/resource
##SBATCH --rsc g=${ngpu}:m=${mem}

#SBATCH --job-name=${name}
#SBATCH --error=${err}
#SBATCH --output=${err}
# ==========================

echo "----- SLURM environment variables ------------------------------------------------------"
echo "number of Cores/Node: \$SLURM_CPUS_ON_NODE"
echo "number of Physical cores per task: \$SLURM_DPC_CPUS"
echo "number of Logical cores per task (twice the value of the physical core): \$SLURM_CPUS_PER_TASK"
echo "Job ID: \$SLURM_JOB_ID"
echo "Parent job ID when executing array job: \$SLURM_ARRAY_JOB_ID"
echo "Task ID when executing array job: \$SLURM_ARRAY_TASK_ID"
echo "Job name: \$SLURM_JOB_NAME"
echo "Name of nodes allocated to the job: \$SLURM_JOB_NODELIST"
echo "Number of nodes allocated to the job: \$SLURM_JOB_NUM_NODES"
echo "Index of executing node in node: \$SLURM_LOCALID"
echo "Index relative to the node allocated to the job: \$SLURM_NODEID"
echo "Number of processes for the job: \$SLURM_NTASKS"
echo "Index of tasks for the job: \$SLURM_PROCID"
echo "Submit directory: \$SLURM_SUBMIT_DIR"
echo "Source host: \$SLURM_SUBMIT_HOST"
echo "--------------------------------------------------------------------------------------"

# Keep track of the execution progress of the job script.
set -x

DATE=\$(date)

echo CUDA_VISIBLE_DEVICES: \$CUDA_VISIBLE_DEVICES
echo ------------------------------------------------------
echo User        : \$USER
echo Path        : \$PATH
echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Sometimes the module command is not available, load it.
source /etc/profile.d/modules.sh

# Here required modules are loaded and environment variables are set
source ~/software/terachem/terachem_environment.sh

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .inp).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/tmp}
jobdir=\$tmpdir/\${SLURM_JOB_ID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy all files back
    cp -rf \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${SLURM_JOB_ID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# TeraChem sometimes requires additional data in external files specified via keywords,
# which have to be copied to the scratch folder on the compute node. We go through all
# files in the current folder and check if they appear in the input file. If yes, they
# are copied. 
for file in *
do
    required=\$(grep "\$file" \$in)
    if [ ! "\$required" == "" ]
    then
       echo "The job needs the file or directory '\$file' => copy it to scratch folder"
       if [ -L "\$file" ] && [ -f "\$file" ] 
       then
          # If file is a symbolic link, copy the file not the link
          cp \$file \$jobdir
       else
          cp -r \$file \$jobdir
       fi
    fi
done

# Go to the scratch folder and run the calculations. Newly created
# files are written to the scratch folder. The log-file is written
# directly to \$out (in the global filesystem).

cd \$jobdir

echo "Files in scratch folder:"
ls -ltah *

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "TeraChem executable: \$(which terachem)"

echo "Running TeraChem ..."
srun terachem \$in &> \$out

# Did the job finish successfully ?
failure=\$(tail -n 20 \$out | grep "DIE called")
if [ "\$failure" == "" ]
then
   echo "TeraChem job finished normally."
   ret=0
else
   echo "TeraChem job failed, see \$out."
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

# Pass return value of TeraChem job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
