#!/bin/bash
#
# To submit a BAGEL input file `molecule.json` to 4 processors
# using 10Gb of memory run
#
#   run_bagel.sh  molecule.json  4   10G
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.json  nproc  mem"
    echo " "
    echo "    submits BAGEL input molecule.json for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The BAGEL log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.json 16  40G"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .json).err
# name of the job which is shown in the queueing table
name=$(basename $job .json)
# number of processors (defaults to 1)
nproc=${2:-1}
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

echo "submitting '$job' (using $nproc processors and $mem of memory)"

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.
# submit to slurm queue
sbatch $sbatch_options <<EOF
#!/bin/bash

# for Slurm
## BAGEL is only installed on bukka-calc
#SBATCH --nodelist=bukka-calc
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${nproc}
#SBATCH --mem=${mem}
#SBATCH --job-name=${name}
#SBATCH --output=${err}

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

echo ------------------------------------------------------
echo Start date: \$DATE
echo ------------------------------------------------------

# Source the script that sets the paths and environment variables for BAGEL.
source /opt/bagel/bagel_environment.sh

# parallelization
export BAGEL_NUM_THREADS=${nproc}
export MKL_NUM_THREADS=${nproc}

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .json).out

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
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${SLURM_JOB_ID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# BAGEL can load geometries, MO coefficients and other data from a binary
# file specified via the keyword 
#   "file": "/path/to/file"
# If such a keyword is detected in the input and the file exists already,
# it will be copied to the scratch folder on the compute node to make them 
# available to BAGEL.
for file in \$(grep "file" \$in | sed 's/"file"\\s*:\\s*//g' | sed 's/[\\",]//g')
do
    # The extension .archive have to be appended to the BAGEL file.
    archive=\${file}.archive
    if [ -f \$archive ]
    then
       echo "The job needs the restart file '\$archive' => copy it to scratch folder"
       cp \$archive \$jobdir
    fi
done

# Molden files can also be used for restarting via the keyword
#   "molden_file" : "/path/to/molden/file"
# They need to be copied to the scratch folder, too.
for file in \$(grep "molden_file" \$in | sed 's/"molden_file"\\s*:\\s*//g' | sed 's/[\\",]//g')
do
    if [ -f \$file ]
    then
       echo "The job needs the restart file '\$file' => copy it to scratch folder"
       cp \$file \$jobdir
    fi
done

# Go to the scratch folder and run the calculations. Newly created
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running BAGEL ..."
srun --mpi=pmi2 BAGEL \$in &> \$out

# Did the job finish successfully ?
failure=\$(tail -n 20 \$out | grep "ERROR")
if [ "\$failure" == "" ]
then
   echo "BAGEL job finished normally."
   ret=0
else
   echo "BAGEL job failed, see \$out."
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

# Pass return value of BAGEL job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
