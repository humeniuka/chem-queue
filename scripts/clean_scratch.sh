#!/bin/bash
#
# remove failed jobs in directory /scratch/humeniuka/g16
# on the compute nodes
#
for i in {1..40}
do
    node=wux$(printf "%2.2d" $i)
    echo "cleaning $node"
    ssh $node 'rm -rf /scratch/${USER}/g16/*.wuxcs/'
done

