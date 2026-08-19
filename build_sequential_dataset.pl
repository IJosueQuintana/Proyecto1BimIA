#!/usr/bin/env perl
use strict;use warnings;use FindBin;use lib $FindBin::Bin;use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetBuilder;use Market::ML::DatasetExporter;
my @files; my $out='datasets/sequential_features_1m.csv'; my $tf=1; my $symbol='MARKET'; my $h=10;
GetOptions('file=s@'=>\@files,'out=s'=>\$out,'timeframe=s'=>\$tf,'symbol=s'=>\$symbol,'target-horizon=i'=>\$h) or die "Uso inválido\n";
@files=@ARGV if !@files;die "Uso: perl build_sequential_dataset.pl --file CSV [--file CSV] [--out archivo]\n" if !@files;
my$b=Market::ML::SequentialDatasetBuilder->new(symbol=>$symbol,timeframe=>$tf,target_horizon=>$h);my@rows;my$cols;for my$f(@files){my$r=$b->build_file_dataset(file=>$f);push@rows,@{$r->{rows}};$cols=$r->{columns};print "$f: $r->{candle_count} candles -> ",scalar(@{$r->{rows}})," rows\n";}
Market::ML::DatasetExporter->new()->export_csv(file=>$out,rows=>\@rows,columns=>$cols);print "Written: $out (",scalar(@rows)," rows)\n";
