#!/bin/bash
#
# To submit a NWCHEM input file `molecule.nw` to 4 processors
# using 10Gb of memory run
#
#   run_nwchem.sh  molecule.nw  4   10Gb
#
# To submit to a specifiy SLURM queue you can set the environment variable
# SBATCH_PARTITION before executing this script, e.g.
#
#   SBATCH_PARTITION=fux  run_nwchem.sh molecule.nw 4 10Gb
#


if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.nw  nproc  mem"
    echo " "
    echo "    submits NWCHEM script molecule.nw for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The log-file is written to molecule.out in the same folder, whereas all other files"
    echo "    created during the run are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.nw 16  40Gb"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .nw).err
# name of the job which is shown in the queueing table
name=$(basename $job .nw)
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
module load numlib/mkl/2019
module load chem/nwchem

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .nw).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=/scratch
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy new files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
    exit
}

trap clean_up SIGHUP SIGINT SIGTERM

# The NEWCHEM job might depend on other files that are referenced in the script
# for instance by the XYZ_PATH keyword. These files have copied to the scratch 
# folder to make them available to the script.
for f in \$(grep -i "XYZ_PATH" \$in | sed 's/XYZ_PATH//gi')
do
   echo "job needs file '\$f' => copy it to scratch folder"
   if [ -f \$f ]
   then
      cp \$f \$jobdir
   else
      echo "\$f not found"
   fi
done

# Go to the scratch folder and run the calculations. Files created by NWChem
# are written to the scratch folder. The log-file is written directly to $out 
# (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running NWChem ..."
mpirun -np ${nproc} nwchem \$in &> \$out

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

