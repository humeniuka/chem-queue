#!/bin/bash
#
# To submit a Molpro input file `molecule.in` to 4 processors
# using 10Gb of memory run
#
#   run_molpro.sh  molecule.in  4   10Gb
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.in  nproc  mem"
    echo " "
    echo "    submits Molpro script molecule.in for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The Molpro log-file is written to molecule.out in the same folder,"
    echo "    whereas other output files (such as cube or molden files etc.) are copied"
    echo "    back from the node only after the calculation has finished."
    echo " "
    echo "    You don't have to specify the amount of memory via the MEMORY card in the script."
    echo "    The amound of words per processor is calculated automatically from 'mem'."
    echo " "
    echo "  Example:  $(basename $0)  molecule.in 16  40Gb"
    echo " "
    exit 
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
# memory in words per processor
mem_words=$(python <<EOF
# compute number of words assigned to each processors
import re
mem="$mem"
nproc=$nproc
# find Kb, Mb or Gb suffix
match=re.match("([0-9]+)([KMGkmg])b", mem)
numbers, units =match.groups()
units = units.lower()
units2words={'k': 1000/8, 'm': 10**6/8, 'g': 10**9/8, 't': 10**12/8}
# Apparently Molpro uses more memory than allowed. We divide the
# allocated memory by 2, so that the job is not killed by the queue.
mem_words=(int(numbers) * units2words[units])/(2*nproc)
print mem_words
EOF
)

# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

# submit to PBS queue
#qsub <<EOF
# submit to slurm queue
sbatch <<EOF
#!/bin/bash

# for Torque
#PBS -q batch
#PBS -l nodes=1:ppn=${nproc},vmem=${mem},mem=${mem}
#PBS -N ${name}
#PBS -jeo 
#PBS -e ${err} 

# for Slurm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=${nproc}
#SBATCH --mem=${mem}
#SBATCH --job-name=${name}
#SBATCH --output=${err}

#NCPU=\$(wc -l < \$PBS_NODEFILE)
NNODES=\$(uniq \$PBS_NODEFILE | wc -l)
DATE=\$(date)
SERVER=\$PBS_O_HOST
SOURCEDIR=\${PBS_O_WORKDIR}

echo ------------------------------------------------------
echo PBS_O_HOST: \$PBS_O_HOST
echo PBS_O_QUEUE: \$PBS_O_QUEUE
echo PBS_QUEUE: \$PBS_O_QUEUE
echo PBS_ENVIRONMENT: \$PBS_ENVIRONMENT
echo PBS_O_HOME: \$PBS_O_HOME
echo PBS_O_PATH: \$PBS_O_PATH
echo PBS_JOBNAME: \$PBS_JOBNAME
echo PBS_JOBID: \$PBS_JOBID
echo PBS_ARRAYID: \$PBS_ARRAYID
echo PBS_O_WORKDIR: \$PBS_O_WORKDIR
echo PBS_NODEFILE: \$PBS_NODEFILE
echo PBS_NUM_PPN: \$PBS_NUM_PPN
echo ------------------------------------------------------
echo WORKDIR: \$WORKDIR
echo SOURCEDIR: \$SOURCEDIR
echo ------------------------------------------------------
echo "This job is allocated on '\${NCPU}' cpu(s) on \$NNODES"
echo "Job is running on node(s):"
cat \$PBS_NODEFILE
echo ------------------------------------------------------
echo Start date: \$DATE
echo ------------------------------------------------------

# Here required modules are loaded and environment variables are set
module load chem/molpro

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .in).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=/scratch
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # remove temporary Molpro files
    rm -f \$jobdir/*.TMP \$jobdir/*.TMP.* \$jobdir/*fort
    # copy output files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running Molpro ..."
set -o xtrace
molpro -m ${mem_words} -n ${nproc} -s -d . -o \$out  \$in 
set +o xtrace
# The results are copied back to the server
# and the scratch directory is cleaned.
echo "Copying results back ..."

clean_up


DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

EOF

echo "submitting '$job' using $nproc processors and $mem of memory ($mem_words words per processors)"

