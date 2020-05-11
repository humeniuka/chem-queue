#!/bin/bash
#
# To submit a Gaussian input file `molecule.gjf` to 4 processors
# using 10Gb of memory run
#
#   run_gaussian.sh  molecule.gjf  4   10Gb
#
# To submit to a specifiy SLURM queue you can set the environment variable
# SBATCH_PARTITION before executing this script, e.g.
#
#   SBATCH_PARTITION=fux  run_gaussian.sh molecule.gjf 4 10Gb
#
# The energy and gradients driving the calculation may be supplied by
# an external call to BAGEL via the keyword
#
#    External="bagel_external.py  input.json"
#
# `input.json` controls the electronic structure calculation, which is
# fed into the geometry optimizer of Gaussian.
#

if [ ! -f "$1" ]
then
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
    echo "  Example:  $(basename $0)  molecule.gjf 16  40Gb"
    echo " "
    echo "  Notes:"
    echo "    The energy and gradients driving the calculation may be supplied by"
    echo "    an external call to BAGEL via the keyword"
    echo " "
    echo "    External=\"bagel_external.py  input.json\""
    echo " "
    echo "   'input.json' controls the electronic structure calculation, which is"
    echo "   fed into the geometry optimizer of Gaussian."
    echo " "


    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .gjf).err
# name of the job which is shown in the queueing table
name=$(basename $job .gjf)
# number of processors (defaults to 1)
nproc=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6Gb}
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
module load g16

# interface between Gaussian and external quantum chemistry codes
module load chem/goptimizer

# Load external quantum chemistry codes
# such as BAGEL
module load devel/boost/1.66
module load compiler/intel/2019
module load chem/bagel

# parallelization
export BAGEL_NUM_THREADS=${nproc}
export MKL_NUM_THREADS=${nproc}

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .gjf).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=/scratch
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

# The external script supplying energy and gradients from a BAGEL calculation
# might require additional JSON files.
for json in \$(grep -i "External=" \$in | sed 's#.*\s\([^[:space:]]*\.json\).*#\\1#')
do
   echo "external program needs JSON file '\$json' => copy it to scratch folder"
   if [ -f \$json ]
   then
      cp \$json \$jobdir
   else
      echo "\$json not found"
   fi
done

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running Gaussian ..."
# Only one processor is used, since the heavy electronic structure calculations
# are done in the external program.
g16 -p=1 < \$in &> \$out

# The results are copied back to the server
# and the scratch directory is cleaned.
echo "Copying results back ..."

clean_up


DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

EOF

echo "submitting '$job' (using $nproc processors and $mem of memory)"

