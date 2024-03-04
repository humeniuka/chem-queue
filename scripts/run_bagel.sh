#!/bin/bash
#
# To submit a BAGEL input file `molecule.json` to 4 processors
# using 10Gb of memory run
#
#   run_bagel.sh  molecule.json  4   10G
#

if [ ! -f "$1" ]
then
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.json  nproc  mem"
    echo " "
    echo "    submits BAGEL input molecule.json for calculation with 'nproc' processors"
    echo "    and memory 'mem'. "
    echo " "
    echo "    The BAGEL log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "  Example:  $(basename $0)  molecule.json 16  40G"
    echo " "
    exit 
fi

# input script
job=$(readlink -f $1)
# errors and output of submit script will be written to this file
err=$(dirname $job)/$(basename $job .json).err
# name of the job which is shown in the queueing table
name=$(basename $job .json)
# number of processors (defaults to 1)
nproc=${2:-1}
# memory (defaults to 6Gb)
mem=${3:-6G}
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

# The submit script is sent directly to stdin of qsub. Note
# that all '$' signs have to be escaped ('\$') inside the HERE-document.

echo "submitting '$job' (using $nproc processors and $mem of memory)"

# submit to PBS queue
qsub $options <<EOF
#!/bin/bash

# ===== PBS options ======
# Specify job queue (partition)
#PBS -q SMALL
# Time limit of 12 hours
#PBS -l walltime=12:00:00
# Request resources
#PBS -l select=1:ncpus=${nproc}:mem=${mem}
# Jobname
#PBS -N ${name}
# Output and errors
#PBS -j eo
#PBS -e ${err}
#PBS -o ${err}
# ==========================

echo "----- PBS environment variables ------------------------------------------------------"
echo "Number of threads, defaulting to number of CPUs: \$NCPUS"
echo "The job identifier assigned to the job: \$PBS_JOBID"
echo "The name of the queue from which the job is executed: \$PBS_QUEUE"
echo "The job-specific temporary directory for this job: \$TMPDIR"
echo "The absolute path of directory where qsub was executed: \$PBS_O_WORKDIR"
echo "--------------------------------------------------------------------------------------"

DATE=\$(date)
echo ------------------------------------------------------
echo Start date: \$DATE
echo ------------------------------------------------------

# Sometimes the module command is not available, load it.
source /etc/profile.d/modules.sh

# Here required modules are loaded and environment variables are set
source $HOME/software/bagel/bagel_environment.sh

# parallelization
export BAGEL_NUM_THREADS=${nproc}
export MKL_NUM_THREADS=${nproc}

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .json).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-/tmp}
jobdir=\$tmpdir/\${PBS_JOBID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # copy all files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${PBS_JOBID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# BAGEL can load geometries, MO coefficients and other data from a binary
# file specified via the keyword 
#   "file": "/path/to/file"
# If such a keyword is detected in the input and the file exists already,
# it will be copied to the scratch folder on the compute node to make them 
# available to BAGEL.
for file in \$(grep "file" \$in | sed 's/"file"\\s*:\\s*//g' | sed 's/[\\",]//g')
do
    # The extension .archive have to be appended to the BAGEL file.
    archive=\${file}.archive
    if [ -f \$archive ]
    then
       echo "The job needs the restart file '\$archive' => copy it to scratch folder"
       cp \$archive \$jobdir
    fi
done

# Molden files can also be used for restarting via the keyword
#   "molden_file" : "/path/to/molden/file"
# They need to be copied to the scratch folder, too.
for file in \$(grep "molden_file" \$in | sed 's/"molden_file"\\s*:\\s*//g' | sed 's/[\\",]//g')
do
    if [ -f \$file ]
    then
       echo "The job needs the restart file '\$file' => copy it to scratch folder"
       cp \$file \$jobdir
    fi
done

# Go to the scratch folder and run the calculations. Newly created
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running BAGEL ..."
BAGEL \$in &> \$out

# Did the job finish successfully ?
failure=\$(tail -n 20 \$out | grep "ERROR")
if [ "\$failure" == "" ]
then
   echo "BAGEL job finished normally."
   ret=0
else
   echo "BAGEL job failed, see \$out."
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

# Pass return value of BAGEL job on to the PBS queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
