#!/usr/bin/env python
# -*- coding: utf-8 -*-
from collections import OrderedDict
import numpy
import json

import sys
import os.path

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
                atom["xyz"] = list(map(float,tmp[1:]))
                geom.append(atom)
    return geom

if len(sys.argv) < 4:
    print( "Usage: %s  template.json  molecule.xyz  molecule.json" % os.path.basename(sys.argv[0]) )
    print( " " )
    print( "  create JSON input file for BAGEL" )
    print( "  All sections are copied from 'template.json' except for the molecule" )
    print( "  section, which is taken from 'molecule.xyz'." )
    print( " " )
    exit(-1)

args = sys.argv[1:]

# load input from template
with open(args[0], "r") as f:
    input_sec = json.load(f)
# find molecule section
for sec in input_sec["bagel"]:
    if sec["title"] == "molecule":
        molecule_sec = sec
        break
else:
    raise RuntimeError("Molecule section not found in JSON template!")

# The geometry in the 'molecule' section is replaced with the one read from the xyz-file.
geom = readXYZ(args[1])
molecule_sec["angstrom"] = True
molecule_sec["geometry"] = geom

# The modified JSON is written to the new input file 
input_filename = args[2]


def to_json(o, level=0, nflag=0):
    """
    serialize an object in the JSON format
    """
    INDENT = 2
    SPACE = " "
    NEWLINE = "\n"

    ret = ""

    if isinstance(o, dict):
        if len(o) == 2:
            ret += NEWLINE + SPACE * INDENT * (level+1) + "{"
        else:
            ret += "{" + NEWLINE

        comma = ""
        for k,v in o.items():
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
    elif isinstance(o, str):
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
    
    
