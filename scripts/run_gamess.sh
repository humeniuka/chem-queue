#!/bin/bash
#
# To submit a GAMESS input file `molecule.inp` to 4 processors
# using 10Gb of memory run
#
#   run_gamess.sh  molecule.inp  4   10Gb
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.inp  nproc  mem"
    echo " "
    echo "    submits GAMESS script molecule.gjf for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The GAMESS log-file is written to molecule.out in the same folder,"
    echo "    whereas the .dat files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo " "
    echo "  Example:  $(basename $0)  molecule.inp 16  40Gb"
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
nproc=${2:-1}
## We need to allocate twice as many processors (compute + data server)
nproc_pbs=$(expr $nproc \* 2)
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

#PBS -q batch
#PBS -l nodes=1:ppn=${nproc_pbs},vmem=${mem},mem=${mem}
#PBS -N ${name}
#PBS -jeo 
#PBS -e ${err} 

# for Slurm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=${nproc_pbs}
#SBATCH --mem=${mem}
#SBATCH --job-name=${name}

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
#module load devel/openmpi/3.0.0
#module load chem/gamess-openmpi
module load chem/gamess

# Input and log-file are not copied to the scratch directory.
in=\$(basename ${job})
out=\$(dirname ${job})/\$(basename ${job} .inp).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=/scratch/\$USER/gamess
jobdir=\$tmpdir/\${PBS_JOBID}
# remove old files in scratch folder
rm -f \${jobdir}/${name}*
# tell GAMESS where to put its temporary files
export TMPDIR=\${jobdir}
# small ASCII supplementary output is also sent to the scratch
export USERSCR=\${jobdir}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy .dat files back
    mv \$jobdir/*.dat $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

# Go to the scratch folder and run the calculations. .dat files
# are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

# copy input file to scratch
cp ${job} \$jobdir
cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running GAMESS on input \$in"
rungms \$in 00 ${nproc} &> \$out 

# The results are copied back to the server
# and the scratch directory is cleaned.
echo "Copying results back ..."

clean_up

echo "FINISHED"

DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

EOF

echo "submitting '$job' (using $nproc processors and $mem of memory)"

