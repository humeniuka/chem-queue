#!/bin/bash
#
# To submit the snakemake workflow in the folder `workflow-folder`
# using 2 CPUs and 6Gb of memory run
#
#   run_snakemake.sh  workflow-folder   2   6G
#

if [ ! -f "$1/Snakefile" ]
then
    echo "There is no Snakefile in folder $1"
    echo " "
    echo "  Usage: $(basename $0)  directory  ncore  mem"
    echo " "
    echo "    submits the Snakemake workflow in 'directory' to the queue using 'ncore' cores"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The log-file and errors are written to snakemake.out in the same folder."
    echo " "
    echo "  Example:  $(basename $0)  ./  2  6G"
    echo " "
    exit 
fi

# The name of the job is taken from the parent folder of the workflow.
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
out=$job/snakemake.out
# name of the job which is shown in the queueing table
name=$(basename $job)
# number of cores (defaults to 1)
ncore=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6G}

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

# The submit script is sent directly to stdin of sbatch. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

>&2 echo "submitting snakemake workflow in '$job' (using $ncore cores and $mem of memory)"

# submit to SLURM queue
sbatch $options <<EOF
#!/bin/bash

# ===== SLURM options ======
# Specify job queue (partition)
#SBATCH -p ${SBATCH_PARTITION:-gr10564b}
# Request resources
# see https://web.kudpc.kyoto-u.ac.jp/manual/en/run/resource
#SBATCH --rsc p=1:c=${ncore}:t=${ncore}:m=${mem}
# Time limit of 7 days
#SBATCH --time=7-00:00:00
#SBATCH --job-name=${name}
#SBATCH --error=${out}
#SBATCH --output=${out}
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

DATE=\$(date)

echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Load conda environment for snakemake
source ~/.bashrc
conda activate snakemake

# Run snakemake workflow
srun snakemake --use-conda --cores ${ncore} --keep-incomplete --rerun-incomplete

DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

# Pass return value of the job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
