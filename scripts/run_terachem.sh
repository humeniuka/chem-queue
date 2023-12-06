#!/bin/bash
#
# To submit a TeraChem input file `molecule.inp` to 2 GPUs
# using 6Gb of memory per GPU run
#
#   run_terachem.sh  molecule.inp   2   6G
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.inp  ngpu  mem"
    echo " "
    echo "    submits TeraChem input molecule.inp for calculation with 'ngpu' GPUs"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The TeraChem log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.inp  2  6G"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .inp).err
# name of the job which is shown in the queueing table
name=$(basename $job .inp)
# number of GPUs (defaults to 1)
ngpu=${2:-1}
# memory (defaults to 1.875G)
mem=${3:-1.875G}
# directory where the input script resides, this were the output
# will be written to as well.
rundir=$(dirname $job)

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

# Each GPU node of typeG has 1.854 Gb of memory. It is not possible to
# request memory independently. The available memory is proportional
# to the number of cores. Therefore the required number of cores
# is calculated from the required amount of memory as
#   cores = (memory / memory-per-core)
# See
#   https://ccportal.ims.ac.jp/en/QuickStart#buildrun_parallel
memory_per_core=1.875

ncore=$(python <<EOF
import numpy
memory="$mem".lower()
if "m" in memory:
   memory = memory.replace("m", "")
   memory = float(memory) / 1024.0
else:
   memory=memory.replace("g", "")
   memory = float(memory)
ncore=int(numpy.ceil(memory / $memory_per_core))
print(ncore)
EOF
)

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

>&2 echo "submitting '$job' (using $ngpu GPUs, $ncore cores and $mem of memory)"

# submit to PBS queue
# RCCS has its own version of qsub which is called jsub and
# unfortunately cannot read the script from stdin.
# Therefore we have to create script first.
cat <<EOF > ${name}.jsub
#!/bin/bash

#PBS -l select=1:ncpus=${ncore}:mpiprocs=1:ompthreads=${ncore}:jobtype=gpu:ngpus=${ngpu}
#PBS -l walltime=24:00:00
#PBS -joe
#PBS -o ${err}
#PBS -e ${err}
#PBS -N ${name}

# Go to the parent folder of the script.
cd ${rundir}

DATE=\$(date)

echo ------------------------------------------------------
echo "Job is running on node(s):"
echo " \$PBS_NODELIST "
echo CUDA_VISIBLE_DEVICES: \$CUDA_VISIBLE_DEVICES
echo ------------------------------------------------------
echo User        : \$USER
echo Path        : \$PATH
echo ------------------------------------------------------
echo Start date  : \$DATE
echo ------------------------------------------------------

# Set environment for TeraChem
source /home/users/eed/software/terachem/terachem_environment.sh

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .inp).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/gwork/users/${USER}}
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy all files back
    cp -rf \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# TeraChem sometimes requires additional data in external files specified via keywords,
# which have to be copied to the scratch folder on the compute node. We go through all
# files in the current folder and check if they appear in the input file. If yes, they
# are copied. 
for file in *
do
    required=\$(grep "\$file" \$in)
    if [ ! "\$required" == "" ]
    then
       echo "The job needs the file or directory '\$file' => copy it to scratch folder"
       if [ -L "\$file" ] && [ -f "\$file" ] 
       then
          # If file is a symbolic link, copy the file not the link
          cp \$file \$jobdir
       else
          cp -r \$file \$jobdir
       fi
    fi
done

# Go to the scratch folder and run the calculations. Newly created
# files are written to the scratch folder. The log-file is written
# directly to \$out (in the global filesystem).

cd \$jobdir

### DEBUG
echo "Files in scratch folder:"
ls -ltah *
###

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "TeraChem executable: \$(which terachem)"

echo "Running TeraChem ..."
terachem \$in &> \$out

# Did the job finish successfully ?
failure=\$(tail -n 20 \$out | grep "DIE called")
if [ "\$failure" == "" ]
then
   echo "TeraChem job finished normally."
   ret=0
else
   echo "TeraChem job failed, see \$out."
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

# Pass return value of TeraChem job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

jsub $options ${name}.jsub
