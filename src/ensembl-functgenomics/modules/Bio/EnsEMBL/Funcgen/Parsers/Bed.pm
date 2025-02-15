#
# EnsEMBL module for Bio::EnsEMBL::Funcgen::Parsers::Bed
#

=head1 LICENSE

  Copyright (c) 1999-2011 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <ensembl-dev@ebi.ac.uk>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=head1 NAME

Bio::EnsEMBL::Funcgen::Parsers::Bed

=head1 SYNOPSIS

  my $parser_type = "Bio::EnsEMBL::Funcgen::Parsers::Bed";
  push @INC, $parser_type;
  my $imp = $class->SUPER::new(@_);


=head1 DESCRIPTION

This is a definitions class which should not be instatiated directly, it 
normally set by the Importer as the parent class.  Bed contains meta 
data and methods specific to data in bed format, to aid 
parsing and importing of experimental data.

=cut

package Bio::EnsEMBL::Funcgen::Parsers::Bed;

use Bio::EnsEMBL::Funcgen::Parsers::InputSet;
use Bio::EnsEMBL::Funcgen::FeatureSet;
use Bio::EnsEMBL::Funcgen::AnnotatedFeature;
use Bio::EnsEMBL::Utils::Exception qw( throw warning deprecate );
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw(open_file is_bed);
use Bio::EnsEMBL::Utils::Argument qw( rearrange );
use Bio::EnsEMBL::Funcgen::Utils::Helper;
use File::Basename;
use strict;

use Data::Dumper;

use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Funcgen::Parsers::InputSet);

#To do
# Extend this so we can import features to annotated_feature
# and profiles/reads to result_feature
# This will replace individual tables for current bed das sources
# Altho' idea of separate tables for each set is not necessarily a bad one
# We would have to have extra table or fields details registration
# Easier admin i.e. drop tables
# What about partitioning? Irrelevant if we are moving to matrix
# Not easy to patch dynamically named tables? Can't assign values to user varaible from query!
# Would need to be a stored procedure
# Could have separate matrix files for result_features as we probably wouldn't want 
# to do any cross set querying at this level.
# Could we also use this in the RunnableDBs?
# Simply separate those methods required by both normal bed annotated_feature import
# and RunnableDB based annotated_feature import
# Importing into result_feature requires a result_set which assumes a chip experiment
# We need to alter result_set such that it can be optionally associated with ExperimentalSets
# Or should we just go for a different table? read_feature?
# NOTE: PARITION by key may run into problems if different sets have different windows
# Would also need to modify ResultFeatureAdaptor?

=head2 new

  Arg[0]     : hash containing optional attributes:
                          -bed_reads => 0|1, #Set input as read alignments rather than peak calls (default is 0)
  Example    : my $self = $class->SUPER::new(@_);
  Description: Constructor method for Bed class
  Returntype : Bio::EnsEMBL::Funcgen::Parsers::Bed
  Exceptions : throws if Experiment name not defined or if caller is not Importer
  Caller     : Bio::EnsEMBL::Funcgen::Importer
  Status     : at risk

=cut

sub new{
  my $caller = shift;
  
  my $class = ref($caller) || $caller;

  my $self = $class->SUPER::new(@_);
  
  throw("This is a skeleton class for Bio::EnsEMBL::Importer, should not be used directly") 
	if(! $self->isa("Bio::EnsEMBL::Funcgen::Importer"));
  
  $self->{'config'} =  
	{(
      #order of these method arrays is important!
	  #remove method arrays and execute serially?
	  #Just move these to individual Parser register_experiment methods
      array_data   => [],#['experiment'],
      probe_data   => [],#["probe"],
      results_data => ["and_import"],
      norm_method => undef,

	  #Need to make these definable?
	  #have protocolfile arg and just parse tab2mage protocol section format
	  #SEE NIMBLEGEN FOR EXAMPLE
	  protocols => {()},
     )};
	
  $self->{'overhang_features'} = [];

  return $self;
}


=head2 set_config

  Example    : my $self->set_config;
  Description: Sets attribute dependent config
  Returntype : None
  Exceptions : None
  Caller     : Bio::EnsEMBL::Funcgen::Importer
  Status     : at risk

=cut


sub set_config{
  my $self = shift;

  $self->SUPER::set_config;

  #Probably need to add MAQ/BOWTIE/BWA as analyses

  #dir are not set in config to enable generic get_dir method access
  #Need to define output dir if we are processing reads
  


  return;
}


sub pre_process_file{
  my ($self, $filepath, $prepare) = @_;

  #Test file format
  throw("Input file is not bed format:\t$filepath") if ! &is_bed($filepath);
  

  #separate sort keys stop lexical sorting of start/end
  #when faced with a non numerical seq_region_name
  my $sort = ($prepare || ! $self->prepared) ? 'sort -k1,1 -k2,2n -k3,3n ' : '';


  if($self->input_gzipped){
	$sort .= '|' if $sort;
	$self->input_file_operator("gzip -dc %s | $sort ");
  }
  else{
	#This is really only required for read alignments
	$self->input_file_operator("$sort %s |");
  }

  
  if(! defined  $self->output_file && $self->input_feature_class eq 'result'){
	my ($name) = fileparse($filepath);
	$name =~ s/\.gz// if $self->input_gzipped;

	if($prepare){
	  #This will be filtered for seq_region_name
	  $self->output_file($self->get_dir('output')."/prepared.${name}.gz");
	}
	else{
	  #Not currently used as we use direct import
	  #via AnnotatedFeatures or ResultFeature Collections

	  #output_file would only be used DAS read mysqlimport loading
	  #This could also be used by SAM/BAM so put in InputSet

	  #Or do we need a file for each discrete set?
	  #Each import consititutes one discrete data set
	  #So this is okay for replicates in a result set
	  #But not for different cell/feature types
	  #Use one file
	  #This is imposed case in INputSet::validate_files
	  #We can't pipe this to gzip as we need to mysqlimport it, which does not support gzip?
	  #gzip -dc file.sql | mysql would work but would be much slower due ti individual inserts
	  #$self->output_file($self->get_dir('output')."/result_feature.${name}.txt");
	}
  }

  return $filepath;
}


#sub parse_header{
#  my ($self, $fh) = @_;
#
#
#  #This will not work on a sorted file, so would have to
#  #store header and test match every line!
#  #just test for track name= for now
#
#
#  warn "PARSING HEADER";
#  my $nr = 0;
#
#  for my $line(<$fh>){
#	$nr++;
#
#	#my $nr = $fh->input_line_number();#This always return 3451? Length of file?
#	#This is not yet reliable here!!!!
#	#Is this because of the gzip sort?
#	#So let's depend on count?
#	#If we don't know when the header is supposed to finish (i.e. multi line header)
#	#We will need to decrement the seek position somehow
#
#	warn "INPUT LINE = $nr $line";
#
#	#exit;
#	if ($nr == 1){#$INPUT_LINE_NUMBER;
#	  #sanity check here
#	  return if($line =~ /track name=/o);
#	  $self->log(":: WARNING ::\tBED file does not appear to have valid header. First line($nr) will be treated as data:\t$line");
#	}
#
#	exit;
#
#  }
#
#
#  exit;
#
# return;
#}



sub parse_line{
  my ($self, $line, $prepare) = @_;

  #Need to handle header here for bed is always $.?
  #Also files which do not have chr prefix? i.e. Ensembl BED rather than UCSC Bed with is also half open coords

  #if ($. == 0){#$INPUT_LINE_NUMBER;
  #	#sanity check here

  return 0 if($line =~ /track name=/o);
  $line =~ s/\r*\n//o;#chump accounts for windows files


  my ($chr, $start, $end, $name, $score, $strand, @other_fields) = split/\s+/o, $line;#Shoudl this not be \t?
  #Should we define minimum fields or microbed format with no naqme and just score?
  #my ($chr, $start, $end, $score) = split/\t/o, $line;#Mikkelson hack	
  #Validate variables types here beofre we get a nasty error from bind_param?

  #Any more valid BED fields here?
  # thickStart - The starting position at which the feature is drawn thickly (for example, the start codon in gene displays).
  # thickEnd - The ending position at which the feature is drawn thickly (for example, the stop codon in gene displays).
  # itemRgb - An RGB value of the form R,G,B (e.g. 255,0,0). If the track line itemRgb attribute is set to "On", this RBG value will determine the display color of the data contained in this BED line. NOTE: It is recommended that a simple color scheme (eight colors or less) be used with this attribute to avoid overwhelming the color resources of the Genome Browser and your Internet browser.
  # blockCount - The number of blocks (exons) in the BED line.
  # blockSizes - A comma-separated list of the block sizes. The number of items in this list should correspond to blockCount.
  # blockStarts - A comma-separated list of block starts. All of the blockStart positions should be calculated relative to chromStart. The number of items in this list should correspond to blockCount. 
  
  my $slice = $self->cache_slice($chr, undef, $prepare);
  #prepare counts total features for RPKM
  #This also filter slices for those defined

  if(! $slice){
	return 0;
  }
  else{
	my $sr_name = $slice->seq_region_name;
	my $slice_name = $slice->name;


	if(! $prepare){

	  $strand = $self->set_strand($strand);			   

	  if($self->ucsc_coords){
		$start +=1;
	  }
	

	  #This is generic count handled in InputSet 
	  $self->count('features');
	  
	  my $feature = Bio::EnsEMBL::Funcgen::AnnotatedFeature->new
		(
		 -START         => $start,
		 -END           => $end,
		 -STRAND        => $strand,
		 -SLICE         => $self->cache_slice($chr),
		 -ANALYSIS      => $self->data_set->product_FeatureSet->analysis,
		 -SCORE         => $score,
		 -DISPLAY_LABEL => $name,
		 -FEATURE_SET   => $self->data_set->product_FeatureSet,
		);

	  
	  $self->annotated_feature_adaptor->store($feature);
	  
	  #Unlikely we will ever need this
	  #dump fasta here
	  #if ($self->dump_fasta()){
	  #  #We need to prefix this with the dbID?
	  #  #And put the fasta in a host:port:dbname specfific dir?
	  #  $fasta .= '>'.$name."\n".$self->cache_slice($chr)->sub_Slice($start, $end, 1)->seq()."\n";
	  #}
	}
  }

  return 1;
}


#For the purposes of creating ResultFeature Collections
#Dependancy on creating features is overkill
#altho not critical as this is never used for display

#Should really move this to InputSet parser
#Altho this would require an extra method call per line to parse the record

sub parse_Features_by_Slice{
  my ($self, $slice) = @_;

  #Slice should have been checked by now in caller  
  if($slice->strand != 1){
	throw("Bed Parser does not support parsing features by non +ve/forward strand Slices\n".
		  'This is to speed up generation of ResultFeature Collections for large sequencing data sets');
  }

  my $slice_chr = $slice->seq_region_name;

  #This method assumes that method calls will walk through a seq_region
  #using adjacent slices
  
  #We need to maintain a feature cache, which contains all the features which over hang
  #the current slice, such that we can include them in the next batch of features returned

  my @features;
  my $slice_end   = $slice->end;
  my $slice_start = $slice->start;
  my $last_slice  = $self->last_slice;
  my $last_slice_end  = ($last_slice) ? $last_slice->end : ($slice_start - 1);  
  my $last_slice_name = ($last_slice) ? $last_slice->seq_region_name : $slice->seq_region_name; 
  my $rset_id = $self->result_set->dbID;
  
  if(! ($slice_start == ($last_slice_end + 1) &&
		($slice->seq_region_name eq $last_slice_name))){
	#Need to reopen the file as we are doing a second pass over the same data
	#This is not guaranteed to work for re-reading sets of slices
	#This would also not be caught by this test

	#To be safe we need to reset the file handle from the caller context

	throw("Bed parser does not yet support parsing features from successive non-adjacent Slices\n".
		  "Last slice end - Next slice start:\t$last_slice_name:${last_slice_end} - ".
		  $slice->seq_region_name.':'.$slice_start);
  }
	
  
  #Deal with 5' overhang first
  foreach my $feature(@{$self->overhang_features}){	
	$feature = $feature->transfer($slice);
	push @features, $feature if $feature;#This should always be true
  }

  $self->{'overhang_features'} = []; #reset overhang features
  my $fh = $self->file_handle;
  my ($line, $feature);
  my $parse = 1;
  #Add counts here, or leave to Collector?
  my $seen_chr = 0;

  #This currently parses the rest of the file once we have seen the data we want

  while((defined ($line = <$fh>)) && $parse){
	#This does not catch the end of the file!


	if($self->last_line){#Deal with previous line first
	  $line = $self->last_line;
	  $self->last_line('');
	}
	else{
	  $line = <$fh>;
	}

	#Still need to chump here in case no other fields
	$line =~ s/\r*\n//o if $line;#chump accounts for windows files

	if(! $line){
	  warn("Skipping empty line");
	  next;
	}

	#We could use a generic method to parse here
	#But it is small enough and simple enough to have twice
	my ($chr, $start, $end, $name, $score, $strand, @other_fields) = split/\s+/o, $line;#Shoudl this not be \t?

	if($slice_chr eq $chr){#Skim through the file until we find the slice
	  $seen_chr = 1;
	  if($end >= $slice_start){

		if($start <= $slice_end){#feature is on slice
		 		
		  $feature =  Bio::EnsEMBL::Funcgen::Collection::ResultFeature->new_fast
			({
			  start         => ($start - $slice_start + 1),
			  end           => ($end - $slice_start + 1),
			  strand        => $strand,
			  scores        => [$score],
			  result_set_id => $rset_id,
			  window_size   => 0,#wsize
			  slice         => $slice,
			 });
		  push @features, $feature;
		
			  if($end > $slice_end){
			#This will also capture last feature which may not be part of current slice
			$self->overhang_features($feature);
		  }
		}
		else{#feature is past end of current slice
		  $parse = 0;
		  $self->last_line($line);#But maybe part of next slice chunk
		}
	  }
	}
	elsif($seen_chr){
	  #We have reached the end of the chromsome!
	  $self->last_line($line);#in case we are parsing slice serially
	  $parse = 0;
	}
  }

  $self->last_slice($slice);

  return \@features;
}

#Move these potentially generic methods to InputSet Parser for use by other Parsers


sub last_line{
 my ($self, $lline) = @_;

 $self->{'last_line'} = $lline if defined $lline;
 return  $self->{'last_line'};

}

sub last_slice{
  my ($self, $lslice) = @_;

  $self->{'last_slice'} = $lslice if $lslice;
  return  $self->{'last_slice'};
}


sub overhang_features{
  my ($self, $feature) = @_;

  push @{$self->{'overhang_features'}}, $feature if $feature;

  return $self->{'overhang_features'};

}

1;
