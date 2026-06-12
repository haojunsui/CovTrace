#!/usr/bin/python3

import glob
import os
import sys

if len(sys.argv) != 2:
    print('Error - Please provide one path to order file directory.')
    exit(1)

# fileDict consists of 'fileName': [lines of order files]
fileDict = {}

# Merge two file, difference of new and base will be added to base
def mergeFileList(base, new):
    mergedFileList = base
    lineStack = []

    base_i = 0

    for i in range(len(new)):
        fileLine = new[i]

        try:
            base_i = mergedFileList.index(fileLine)

            if len(lineStack) > 0:
                if base_i == 0:
                    mergedFileList = lineStack + mergedFileList
                else:
                    mergedFileList = mergedFileList[0:(base_i - 1)] + lineStack + mergedFileList[(base_i - 1):]

            lineStack = []
        except ValueError:
            lineStack.append(fileLine)

    if len(lineStack) > 0:
        mergedFileList.extend(lineStack)

    return mergedFileList


for filePath in glob.iglob(sys.argv[1] + '/**', recursive=True):
    if filePath.endswith(".order"): 
        fileName = os.path.basename(filePath)
        with open(filePath) as f:
            fileLines = f.read().splitlines()

        if fileDict.get(fileName) == None:
            fileDict[fileName] = fileLines
        else:
            fileDict[fileName] = mergeFileList(fileDict[fileName], fileLines)
        continue
    else:
        continue

outputDirectory = sys.argv[1] + '/Merged/'

if not os.path.exists(outputDirectory):
    os.makedirs(outputDirectory)

for fileName, fileList in fileDict.items():
    with open(outputDirectory + fileName, 'w') as f:
        for line in fileList:
            f.write(f"{line}\n")