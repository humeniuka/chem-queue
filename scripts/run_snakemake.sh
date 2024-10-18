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
    echo "  Usage: $(basename $0)  directory  nproc  mem  [ncore]"
    echo " "
    echo "    submits the Snakemake workflow in 'directory' to the queue using 'nproc' processes"
    echo "    and memory 'mem'. If specified, the number of concurrent jobs 'ncore' can be larger than"
    echo "    the number of processes."
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
nproc=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6G}
# number of concurrent jobs
ncore=${4:-${nproc}}

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

# convert memory resources from Gb to Mb
mem_mb=$(python <<EOF
memory="$mem".lower()
if "m" in memory:
   mem_mb=int(memory.replace('m', '').replace('b', ''))
elif "g" in memory:
   mem_mb=int(memory.replace('g', '').replace('b', '')) * 1024
print(mem_mb)
EOF
)

# The submit script is sent directly to stdin of sbatch. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

>&2 echo "submitting snakemake workflow in '$job' (using $nproc processes and $mem of memory, $ncore concurrent jobs)"

# submit to SLURM queue
sbatch $options <<EOF
#!/bin/bash

# for Slurm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=${nproc}
#SBATCH --mem=${mem}
#SBATCH --job-name=${name}
#SBATCH --output=${err}

DATE=\$(date)

echo ------------------------------------------------------
echo SLURM_SUBMIT_HOST: \$SLURM_SUBMIT_HOST
echo SLURM_JOB_NAME: \$SLURM_JOB_NAME
echo SLURM_JOB_ID: \$SLURM_JOB_ID
echo SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR
echo SLURM_CPUS_ON_NODE: \$SLURM_CPUS_ON_NODE
echo ------------------------------------------------------
echo "Job is running on node(s):"
echo " \$SLURM_NODELIST "
echo PROCESSORS: ${nproc}
echo MEMORY: ${mem}
echo "CPUINFO: \$(cat /proc/cpuinfo | awk '/model name/ {print \$0}' | head -n 1)"
echo ------------------------------------------------------
echo User        : \$USER
echo Path        : \$PATH
echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Load conda environment for snakemake
source ~/.bashrc
module purge
module load mamba
mamba activate snakemake

# Run snakemake workflow
snakemake \
     --use-conda --cores ${ncore} \
     --resources mem_mb=${mem_mb} \
     --keep-incomplete --rerun-incomplete

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
