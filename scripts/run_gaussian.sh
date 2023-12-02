#!/bin/bash
#
# To submit a Gaussian input file `molecule.gjf` to 4 processors
# using 10G of memory run
#
#   run_gaussian.sh  molecule.gjf  4   10G
#
# To submit to a specifiy SLURM queue you can set the environment variable
# SBATCH_PARTITION before executing this script, e.g.
#
#   SBATCH_PARTITION=fux  run_gaussian.sh molecule.gjf 4 10G
#

show_help() {
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.gjf  nproc  mem"
    echo " "
    echo "    submits Gaussian script molecule.gjf for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The Gaussian log-file is written to molecule.out in the same folder,"
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

# Additional options for sbatch must precede all arguments
options=""
while :; do
    case $1 in
	-h|--help)
	    show_help
	    ;;
	-w|--wait)
	    echo "Script will hang until the job finishes."
	    options="${options} --wait"
	    shift
	    ;;
	--)
	    # end of options
	    shift
	    break
	    ;;
	*)
	    # default case
	    break
    esac
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
ncore=${2:-1}
# memory (defaults to 2G)
mem=${3:-2G}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

echo "submitting '$job' (using $ncore cores and $mem of memory)"

# submit to PBS queue
#qsub <<EOF
# submit to slurm queue
sbatch $options <<EOF
#!/bin/bash

# ===== SLURM options ======
# Specify job queue (partition)
#SBATCH -p ${SBATCH_PARTITION:-gr10564b}
# Time limit of 7 days
#SBATCH -t 7-0:0:0
# Request resources
# see https://web.kudpc.kyoto-u.ac.jp/manual/en/run/resource
#SBATCH --rsc p=1:c=${ncore}:t=${ncore}:m=${mem}

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

echo ------------------------------------------------------
echo Start date: \$DATE
echo ------------------------------------------------------


# Here required modules are loaded and environment variables are set
module load gaussian16

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .gjf).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/tmp}
jobdir=\$tmpdir/\${SLURM_JOB_ID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # remove temporary Gaussian files
    rm -f \$jobdir/Gau-*
    # copy checkpoint files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${SLURM_JOB_ID}/*
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
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running Gaussian ..."
srun g16 -p=${ncore} < \$in &> \$out

# Did the job finish successfully ?
success=\$(tail -n 1 \$out | grep "Normal termination of Gaussian")
if [ "\$success" ]
then
   echo "Gaussian job finished normally."
   ret=0
else
   echo "Gaussian job failed, see \$out."
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

# Pass return value of Gaussian job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?


