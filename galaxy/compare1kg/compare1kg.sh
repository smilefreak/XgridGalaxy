#!/bin/bash

# FIXME: All references of 1kg are no longer true as we now use evs too.
# $1 = my vcf
# $2 = <= || >=
# $3 = value for grep in myvcf
# $4 = <= || >=
# $5 = value for grep in 1kg
# $6 = SNPs or Indels
# $7 = output vcf
# $8 = database
# $9 = population (optional)

if [ "$8" == "1kg" ] 
then
    DATABASE=`ls ~/galaxy-dist/tools/SOER1000genes/data/1kg/vcf/ALL.*.gz`
else
    DATABASE=`ls ~/galaxy-dist/tools/SOER1000genes/data/evs/esp/ESP6500.ALL.snps.vcf.gz`
fi

# Print out header into new file
while read line
    do
        HEADER=`echo $line | awk '{if ($1 ~ /^#/) {print $0}}'`
        if [ "$HEADER" == "" ]
        then
            break
        fi

        echo $HEADER >> $7

done < $1

# Filter original

~/galaxy-dist/tools/SOER1000genes/galaxy/compare1kg/./alleleFreqFilter.sh $1 $3 $2 $6 $8 $9 >| filtered_myVCF.vcf

# get positions from filtered original
awk '{print $1":"$2"-"$2}' < filtered_myVCF.vcf >| pos1.txt

bgzip filtered_myVCF.vcf
tabix -fp vcf filtered_myVCF.vcf.gz

# gets position from my filtered vcf
while read line
    do
        tabix -f $DATABASE $line >> filtered.1kg.vcf
    done < pos1.txt
#filter 1kg vcf
~/galaxy-dist/tools/SOER1000genes/galaxy/compare1kg/./alleleFreqFilter.sh `pwd`/filtered.1kg.vcf $5 $4 $6 $8 $9 >| final_filtered_1kg.vcf
awk '{print $1":"$2"-"$2}' < final_filtered_1kg.vcf >| pos2.txt
# print out all those that match the 1kg and myvcf
while read line
    do
       tabix -f filtered_myVCF.vcf.gz $line >> $7
       
    done < pos2.txt

exit 0

