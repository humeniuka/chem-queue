#!/bin/bash
#
# Run a command string via the PBS or Slurm queue, for example
#
#   run_gamess.sh  "ls -l | wc -l"  4   10Gb
#

if [ $# == 0 ]
then
    echo " "
    echo "  Usage: $(basename $0)  command  nproc  mem"
    echo " "
    echo "    submits a command (enclosed in quotation marks) to the queue with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    A filename for the output is constructed from the command string by replacing special"
    echo "    characters with underscores. The output is written directly to the network filesystem"
    echo "    in the current working directoy."
    echo " "
    echo "  Example:  $(basename $0)  'ls -l | wc -l; sleep 10'  2  2Gb"
    echo " "
    echo "    The output is written to   ls_-l___wc_-l__sleep_10.out  in the current folder."
    echo " "
    exit 
fi

cmd=$1
# Create a UNIX filename from the command
name="${cmd//[^[:alnum:]._-]/_}"
# errors and output of submit script will be written to this file
out=$(pwd)/${name}.out
# number of processors (defaults to 1)
nproc=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6Gb}

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

# submit to PBS queue
#qsub <<EOF
# submit to slurm queue
sbatch <<EOF
#!/bin/bash

# for Slurm
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${nproc}
#SBATCH --mem=${mem}
#SBATCH --job-name=${name}
#SBATCH --output=${out}

echo ------------------------------------------------------
echo SLURM_SUBMIT_HOST: \$SLURM_SUBMIT_HOST
echo SLURM_JOB_NAME: \$SLURM_JOB_NAME
echo SLURM_JOB_ID: \$SLURM_JOB_ID
echo SLURM_SUBMIT_DIR: \$SLURM_SUBMIT_DIR
echo SLURM_CPUS_ON_NODE: \$SLURM_CPUS_ON_NODE
echo ------------------------------------------------------
echo "Job is running on node(s):"
echo " \$SLURM_NODELIST "
echo ------------------------------------------------------
echo User        : \$USER
echo Path        : \$PATH
echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Sometimes the module command is not available, load it.
source /etc/profile.d/modules.sh

# Here required modules are loaded and environment variables are set
export PYTHONUNBUFFERED=1

cd \$SLURM_SUBMIT_DIR

echo "Running command '$cmd'"
echo "   ##### START #####"
$cmd
echo "   ##### FINISH ####"

DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

EOF

echo "Submitting command '$cmd' (using $nproc processors and $mem of memory)"
echo "Output will be written to '$out'."
