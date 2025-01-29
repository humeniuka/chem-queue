#!/bin/bash
#
# To submit a ORCA input file `molecule.inp` using 10Gb of memory run
#
#   run_orca.sh  molecule.inp  10G
#

show_help() {
    echo "Input script $1 does not exist!"
    echo " "
    echo "  Usage: $(basename $0)  molecule.inp  mem"
    echo " "
    echo "    submits ORCA script molecule.inp for calculation with memory 'mem'. "
    echo " "
    echo "    The ORCA log-file is written to molecule.out in the same folder,"
    echo "    whereas all other files are copied back from the node only after the calculation "
    echo "    has finished."
    echo " "
    echo "    The number of parallel processes should be specified in the ORCA script."
    echo " "
    echo "  Example:  $(basename $0)  molecule.inp 40G"
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
err=$(dirname $job)/$(basename $job .inp).err
# name of the job which is shown in the queueing table
name=$(basename $job .inp)
# memory (defaults to 6Gb)
mem=${2:-6G}
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

# Determine the number of processes to use by parsing the %pal ... end
# section in the Orca input file.
nproc=1
# The number of processes can be specified in two different formats
# in the Orca input file, either as
#   % pal  nprocs  8  end
# or as
#   !PAL8
nproc_format_1=$(grep -Poie '^%PAL[[:space:]]*nprocs[[:space:]]*\K([[:digit:]]+)' $job | tail -n 1)
nproc_format_2=$(grep -Poie '![[:space:]]*PAL[[:space:]]*\K([[:digit:]]+)' $job | tail -n 1)

if [ "$nproc_format_1" != "" ]
then
   nproc=$nproc_format_1
elif [ "$nproc_format_2" != "" ]
then
   nproc=$nproc_format_2
else
   # By default a single process is used
   nproc=1
   echo "WARNING:"
   echo "    The Orca input script does not specify the number of processes."
   echo "    Add the line '%pal nprocs 8 end' in $job to run a calculation with 8 processes."
fi

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

cd \$SLURM_SUBMIT_DIR

# Here required modules are loaded and environment variables are set
source ~/.bashrc
module purge
module load orca/6.0
module load xtb

# This should be put into the modulefile for orca/6.0
export XTBEXE=\$(which xtb)

echo "Loaded modules"
module list

# Input and log-file are not copied to the scratch directory.
in=${job}
name=\$(basename \$in .inp)
out=\$(dirname \$in)/\${name}.out

# Calculations are performed in the user's scratch 
# directory. For each job a directory is created
# whose contents are later moved back to the server.

tmpdir=\${SCRATCH:-tmp}
jobdir=\$tmpdir/orca_\${SLURM_JOB_ID}

mkdir -p \$jobdir

# If the script receives the SIGTERM signal (because it is removed
# using the scancel command), the intermediate results are copied back.

function clean_up() {
    # remove temporary files
    rm -f \$jobdir/*.tmp
    # copy other files back
    mv \$jobdir/* $rundir/
    # delete temporary folder
    rm -f \$tmpdir/orca_\${SLURM_JOB_ID}/*
}

trap clean_up SIGHUP SIGINT SIGTERM

# Copy xyz-files needed by the job to the scratch folder
for xyzfile in *.xyz \$(cat \$in | awk 'BEGIN {IGNORECASE=1} /\* xyzfile/ {print \$5}')
do
   # Remove quotes around filename.
   xyzfile=\$(echo \$xyzfile | tr -d '"')
   echo "job needs external xyzfile '\$xyzfile' => copy it to scratch folder"
   if [ -f \$xyzfile ]
   then
      cp \$xyzfile \$jobdir
   else
      echo "\$xyzfile not found"
   fi
done

# Copy Hessian files needed by the job to scratch folder.
for hessfile in \$(cat \$in | awk '/GSHESSIAN/ {print \$2} /ESHESSIAN/ {print \$2}')
do
   # Remove quotes around filename.
   hessfile=\$(echo \$hessfile | tr -d '"')
   echo "job needs external Hessian file '\$hessfile' => copy it to scratch folder"
   if [ -f \$hessfile ]
   then
      cp \$hessfile \$jobdir
   else
      echo "\$hessfile not found"
   fi
done

# Go to the scratch folder and run the calculations. Checkpoint
# files are written to the scratch folder. The log-file is written
# directly to \$out (in the global filesystem).

cd \$jobdir

echo "Calculation is performed in the scratch folder"
echo "   \$(hostname):\$jobdir"

cp \$in \${name}.inp

echo "Running ORCA ..."
echo "Path to orca executable: \$ORCA"
time \$ORCA \${name}.inp &> \$out

echo "Creating molden file ..."
# Create a molden file for visualizing orbitals
orca_2mkl \${name} -molden

# Did the job finish successfully ?
success=\$(grep "ORCA TERMINATED NORMALLY" \$out)
if [ "\$success" ]
then
   echo "ORCA job finished normally."
   ret=0
else
   echo "ORCA job failed, see \$out."
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

# Pass return value of ORCA job on to the SLURM queue, this allows
# to define conditional execution of dependent jobs based on the 
# exit code of a previous job.
echo "exit code = \$ret"
exit \$ret

EOF

# submit to slurm queue
echo "submitting '$job' (using $nproc processors and $mem of memory)"
sbatch $options ${name}.job

# Exit code of 'sbatch --wait ...' is the output of the batch script, i.e. $ret.
exit $?
