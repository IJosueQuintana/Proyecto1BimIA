#!/usr/bin/env perl
use strict;use warnings;use FindBin;use lib $FindBin::Bin;use Market::ML::SequentialDatasetAuditor;
my$file=shift or die "Uso: perl audit_sequential_dataset.pl dataset.csv\n";open my$fh,'<',$file or die$!;my$h=<$fh>;chomp$h;my@c=split/,/,$h;my@r;while(<$fh>){chomp;next if/^\s*$/;my@v=split /,/, $_, -1;my%row;for my$i(0..$#c){$row{$c[$i]}=$v[$i]}push@r,\%row;}close$fh;my$a=Market::ML::SequentialDatasetAuditor->new;my$d=$a->audit(rows=>\@r);$a->print_report($d);
