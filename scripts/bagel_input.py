#!/usr/bin/env python
# -*- coding: utf-8 -*-
from collections import OrderedDict
import numpy as np

import sys
import os.path

if len(sys.argv) < 3:
    print ""
    print "Usage: %s  molecule.xyz  molecule.json" % os.path.basename(sys.argv[0])
    print "  create JSON input file for BAGEL"
    print ""
    exit(-1)

geometry = sys.argv[1]
input_filename = sys.argv[2]
basis = "svp"   
df_basis = "svp-jkfit"  # density fitting basis set, ri apprx
method = "casscf"
job = "energy"
nstate = 2
state_of_interest = 1 # S0 = 0, S1 =1, ...
nact = 8   # number of active orbitals

atoms = np.loadtxt(geometry, skiprows=2, usecols=[0], dtype=str)
electrons = {"H": 1, "C": 6, "N": 7, "O":  8, "S": 16, "Zn": 30}
nelec = np.sum([electrons[atom] for atom in atoms])
nclosed = (nelec - nact) / 2  # number of closed orbitals

def readXYZ(filename):
    # read molecular coordinates from .xyz file
    # return list of symbols and list of coordinate
    geom = [] 
    with open(filename, "r") as f:
        for line in f:
            tmp=line.split()
            if len(tmp)==4: 
                atom = OrderedDict()
                atom["atom"] = tmp[0]
                atom["xyz"] = map(float,tmp[1:])
                geom.append(atom)
    return geom

geom = readXYZ(geometry)

method_sec = OrderedDict()
method_sec["title"] = method
method_sec["nstate"] = nstate
method_sec["nact"] = nact
method_sec["natocc"] = True
method_sec["nclosed"] = nclosed
method_sec["dipoles"] = True

molecule_sec = OrderedDict()
molecule_sec["title"] = "molecule"
molecule_sec["basis"] = basis
molecule_sec["df_basis"] = df_basis
molecule_sec["angstrom"] = True
molecule_sec["geometry"] = geom

job_sec = OrderedDict()
job_sec["title"] = "optimize"
job_sec["opttype"] = job
job_sec["target"] = state_of_interest
job_sec["maxstep"] = 0.05
job_sec["method"] = [method_sec]

print_sec = OrderedDict()
print_sec["title"] = "print"
print_sec["file"] = "orbitals.molden"
print_sec["orbitals"] = True

read_sec = OrderedDict()
read_sec["title"] = "load_ref"
read_sec["file"] = "mo_coeff"
read_sec["continue_geom"] = False

save_sec = OrderedDict()
save_sec["title"] = "save_ref"
save_sec["file"] = "mo_coeff"

input_sec = OrderedDict()
input_sec["bagel"] = [molecule_sec, read_sec, job_sec, print_sec, save_sec]
            

INDENT = 2
SPACE = " "
NEWLINE = "\n"

def to_json(o, level=0, nflag=0):
    ret = ""

    if isinstance(o, dict):
        if len(o) == 2:
            ret += NEWLINE + SPACE * INDENT * (level+1) + "{"
        else:
            ret += "{" + NEWLINE

        comma = ""
        for k,v in o.iteritems():
            ret += comma
            if k == "atom":
                comma = ","
            else:
                comma = ",\n"
            if k != "xyz" and k != "atom":
                ret += SPACE * INDENT * (level+1)
            ret += '"' + str(k) + '":' + SPACE
            ret += to_json(v, level + 1, nflag=nflag)
        if k == "xyz":
            ret += " }"
        else:
            nflag = 0
            ret += NEWLINE + SPACE * INDENT * level + "}"
    elif isinstance(o, basestring):
        ret += '"' + o + '"'
    elif isinstance(o, list):
        ret += "[" + ",".join([to_json(e, level+1) for e in o]) + "]"
    elif isinstance(o, bool):
        ret += "true" if o else "false"
    elif isinstance(o, int):
        ret += str(o)
    elif isinstance(o, float):
        ret += '%12.8f' % o
    elif isinstance(o, numpy.ndarray) and numpy.issubdtype(o.dtype, numpy.integer):
        ret += "[" + ','.join(map(str, o.flatten().tolist())) + "]"
    elif isinstance(o, numpy.ndarray) and numpy.issubdtype(o.dtype, numpy.inexact):
        ret += "[" + ','.join(map(lambda x: '%.7g' % x, o.flatten().tolist())) + "]"
    else:
        raise TypeError("Unknown type '%s' for json serialization" % str(type(o)))
    return ret
 
 
#print to_json(input_sec)
with open(input_filename, "w") as f:
    f.writelines(to_json(input_sec))
    
    
