#!/bin/bash
#
# To submit a OpenMolcas input file `molecule.input` to 4 processors
# using 10Gb of memory run
#
#   run_openmolcas.sh  molecule.input  4   10Gb
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.input  nproc  mem"
    echo " "
    echo "    submits OpenMolcas input molecule.input for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.input 16  40Gb"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .input).err
# name of the job which is shown in the queueing table
name=$(basename $job .input)
# number of processors (defaults to 1)
nproc=${2:-1}

if [ "$nproc" -gt 1 ]
then
    echo "OpenMolcas has been compiled for serial execution, but got proc=$nproc !"
    exit 
fi

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

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .input).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=/scratch
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# Here required modules are loaded and environment variables are set
module load chem/openmolcas/latest

# set environment variables used by MOLCAS
# additional output is written to this folder
export MOLCAS_OUTPUT=$rundir
# parent directory for all scratch areas
export MOLCAS_WORKDIR=\$jobdir
export MOLCAS_PROJECT=$name
# parallelization
export MOLCAS_NPROC=${nproc}
# memory
export MOLCAS_MEM=${mem}
# remove scratch area after calculation
export MOLCAS_KEEP_WORKDIR=NO

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy all files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

# MOLCAS loads geometries from an external file specified via the keyword
#   coord=molecule.xyz
# If such a keyword is detected in the input and the file exists, it will 
# be copied to the scratch folder on the compute node to make it 
# available to MOLCAS.
for file in \$(grep "coord=" \$in | sed 's/coord\\s*=\\s*//g')
do
    if [ -f \$file ]
    then
       echo "The job needs the coord file '\$file' => copy it to scratch folder"
       cp \$file \$jobdir
    fi
done

# Go to the scratch folder and run the calculations. Newly created
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running OpenMolcas ..."
pymolcas \$in &> \$out

# remove empty folder
rmdir \$MOLCAS_PROJECT

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

