#!/usr/bin/perl

use strict;

# -----------------------------------------------------------------------------
# Function:  parse_input
# Description:  Parses inputfile and writes it as a CSV format to outputfile
#------------------------------------------------------------------------------
sub parse_input {
  my ($inputfile, $outputfile) = @_;  #arguments passed
  my @headers;  #array that will contain the iostat headers
  my @values;  #array that will contain the values of headers
  my $input_fh;  #input file handle
  my $output_fh; #output file handle
  my $time_stamp;  #holds the time stamp
  my $linenum=0;  #total count of lines successfully parsed

  my $skip_next_line=0;  # skips the line being parsed if flag is set

  # perform file io checks
  open($input_fh, '<', $inputfile) or die "Could not read file '$inputfile' $!";
  open($output_fh, '>', $outputfile) or die "Could not write to file '$outputfile' $!";

  # go line by line through input file
  while (my $line = <$input_fh>) {
    chomp($line);  # remove end of line character

    #print "DEBUG: Looking at [$line]\n";

    if ($skip_next_line){  # Skip this line if skip flag was set
      $skip_next_line=0; #reset flag
      next;
    }
    elsif (length($line) < 1){  # Skip this line if it's empty
      #print "DEBUG: line is empty\n";
      next;
    }
    elsif ($line =~ /^([\/:\d\s]+\wM)$/) { # A line with '/' and ':' that ends in either PM or AM must be a time stamp
      $time_stamp=$1;
      #print "DEBUG: Time is [$time_stamp]\n";
    }
    elsif ($line =~ /avg-cpu/i){ # Found a subheader for CPU info. This script will ignore this information.
      $skip_next_line=1; #skip the following line too as it will be data for cpu info
      next;
    }
    elsif($line =~ /Device/  ){ # A line with 'Device' is the header
      if (scalar(@headers)<1) { #save headers only once
        foreach my $header (split(/\s+/, $line)){
            push(@headers, $header);
        }
        #print "DEBUG: Headers are [" . join( ',', @headers) . "]\n";
      }
    }
    elsif(scalar(@headers)>1){ # parse values once header is found
      @values=(); #clear array of previous values
      foreach my $value (split(/\s+/, $line)){ #values should be seperated by empty spaces
        push(@values, $value);
      }
      if ( scalar(@headers) != scalar(@values) ) { #make sure number of values and headers are equal
        print("WARNING: Found " . scalar(@headers) . " headers but only " . scalar(@values) . " values\n");
      }
      #print "DEBUG: Found " . scalar(@values) . " values\n";

      if ($linenum == 0){  #print header only once
        print $output_fh "Time,";
        print $output_fh join( ',', @headers);
        print $output_fh "\n";
      }
      print $output_fh $time_stamp . ",";
      print $output_fh join( ',', @values);
      print $output_fh "\n";

      $linenum++;
    }
  }

  close $output_fh;
  close $input_fh;
  print("Successfully parsed $linenum lines and saved output to $outputfile\n");
}
# -----------------------------------------------------------------------------
# MAIN STARTS HERE
#------------------------------------------------------------------------------

my $file_path='';
my $output_file='iostats.csv';

if ( scalar(@ARGV) > 0 ){  # the first argument is the file input
  $file_path=$ARGV[0];
}
else {
  printf("Syntax: iostat_parser {file_input_path} [file_output_path]\n\n");
  printf("ERROR : Please provide the path of the input file to parse as an argument\n");
  exit 1;
}

if ( scalar(@ARGV) > 1 ){  # the second argument is the file output
  $output_file=$ARGV[1];
}

unless( -e $file_path ){  # check input file
  printf("Syntax: iostat_parser {file_input_path} [file_output_path]\n\n");
  printf("ERROR : The file %s does not exist\n", $file_path);
  exit 1;
}

parse_input($file_path, $output_file);  #perform actual parsing
