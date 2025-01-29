#!/bin/bash
#
# To submit a Gaussian input file `molecule.gjf` to 4 processors
# using 10Gb of memory run
#
#   run_gaussian.sh  molecule.gjf  4   10G
#

show_help() {
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
    echo "  Example:  $(basename $0)  molecule.gjf 16  40G"
    echo " "
    exit 1
}

if [ ! -f "$1" ]
then
    show_help
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

# Create submission script
# Note that all '$' signs have to be escaped ('\$') inside the HERE-document.
cat > ${name}.job <<EOF
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

# Here required modules are loaded and environment variables are set
source ~/.bashrc
module purge
module load gaussian

echo "Loaded modules"
module list

# Input and log-file are not copied to the scratch directory.
in=${job}
out=\$(dirname \$in)/\$(basename \$in .gjf).out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${GAUSS_SCRDIR:-tmp}
jobdir=\$tmpdir/\${SLURM_JOB_ID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the qdel command), the intermediate results are copied back.

function clean_up() {
    # remove temporary Gaussian files
    rm -f \$jobdir/Gau-*
    # copy checkpoint files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/\${SLURM_JOB_ID}/*
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

# The job might need other checkpoint files which are listed at the
# end of the input (for instance for Franck-Condon spectra.)
for oldchk in \$(grep "^[^%].*.\.chk" \$in)
do
   echo "job needs additional checkpoint file '\$oldchk' => copy it to scratch folder"
   if [ -f \$oldchk ]
   then
      cp \$oldchk \$jobdir
   else
      echo "\$oldchk not found"
   fi
done

# Copy external @-files (geometries, basis sets) to the scratch folder
for atfile in \$(grep -i "^@" \$in | sed 's/@//gi')
do
   echo "job needs external file '\$atfile' => copy it to scratch folder"
   if [ -f \$atfile ]
   then
      cp \$atfile \$jobdir
   else
      echo "\$atfile not found"
   fi
done

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to $out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

echo "Running Gaussian ..."
time g16 -p=${nproc} < \$in &> \$out

# Did the job finish successfully ?
success=\$(tail -n 1 \$out | grep "Normal termination of Gaussian")
if [ "\$success" ]
then
   echo "Gaussian job finished normally."
   ret=0
else
   echo "Gaussian job failed, see \$out."
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

# Pass return value of Gaussian job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# submit to slurm queue
>&2 echo "submitting '$job' (using $nproc processors and $mem of memory)"
sbatch $options ${name}.job

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
