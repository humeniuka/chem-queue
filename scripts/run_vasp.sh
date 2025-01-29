#!/bin/bash
#
# To start a VASP calculation in the current folder with 4 processors
# using 10Gb of memory run
#
#   run_vasp.sh INCAR.name   4   10G
#

show_help() {
    cat <<EOF
    Input $1 does not exist

        Usage: $(basename $0) name.INCAR  cpus  memory

    Submits a VASP calculation with the requested number of cpus and memory to the queue
    using the specified INCAR.
    INCAR files should have different names to distinguish different calculations.
    The name is prepended to the outputs of the VASP calculations (name.OUTCAR, name.vasprun.xml). 
    
        Example:  $(basename $0)  dft.INCAR  16  40G
EOF
}

if [ ! -f "$1" ]
then
    show_help
    exit -1
fi

pattern='.*\.INCAR'
if [[ ! $1 =~ $pattern ]]
then
    echo "Please prepend a name to INCAR, e.g. dft.INCAR instead of just INCAR."
    exit -1
fi

# input script
incar=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $incar)/$(basename $incar .INCAR).err
# name of the job which is shown in the queueing table
name=$(basename $incar .INCAR)
# number of processors (defaults to 16)
cpus=${2:-16}
# memory (defaults to 24Gb)
mem=${3:-24G}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $incar)

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

# Create submission script
# Note that all '$' signs have to be escaped ('\$') inside the HERE-document.
cat > ${name}.sbatch <<EOF
#!/bin/bash

# for Slurm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=${cpus}
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
echo PROCESSORS: ${cpus}
echo MEMORY: ${mem}
echo "CPUINFO: \$(cat /proc/cpuinfo | awk '/model name/ {print \$0}' | head -n 1)"
echo ------------------------------------------------------
echo User        : \$USER
echo Path        : \$PATH
echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Here required modules are loaded and environment variables are set
module purge
module load vasp

echo "Loaded modules"
module list

SOURCEDIR=$rundir

export VASP_WORKDIR="/scratch/\$USER/VASP/\$SLURM_JOB_ID"

test -d \$VASP_WORKDIR || mkdir -m700 -p \$VASP_WORKDIR
cp \$SOURCEDIR/* \$VASP_WORKDIR/
# Copy the name.INCAR to INCAR
cp $incar \$VASP_WORKDIR/INCAR
cd \$VASP_WORKDIR

# Run VASP
export OMP_NUM_THREADS=1
export SRUN_CPUS_PER_TASK=\$SLURM_CPUS_PER_TASK

mpirun -np ${cpus} vasp_std
ret=\$?

# Give VASP some time to finish writing all files.
sleep 3

# Prepend name to output files
mv OUTCAR ${name}.OUTCAR
mv vasprun.xml ${name}.vasprun.xml

# Copy the files back
cp * \$SOURCEDIR

# Remove scratch folder
rm -r \$VASP_WORKDIR/*

DATE=\$(date)
echo ------------------------------------------------------
echo End date: \$DATE
echo ------------------------------------------------------

# Pass return value of VASP job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# submit to slurm queue
>&2 echo "submitting '$incar' (using $cpus processors and $mem of memory)"
sbatch $options ${name}.sbatch

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
