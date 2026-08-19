package Market::ML::SequentialDatasetAuditor;
use strict;
use warnings;
use List::Util qw(min max);
use Market::ML::SequentialFeatureSchema;
sub new { my ($class)=@_; return bless {},$class; }
sub audit {
 my ($self,%args)=@_; my $rows=$args{rows}//[]; my $features=Market::ML::SequentialFeatureSchema->feature_columns;
 my (%constant,%missing,%counts);
 for my $column (@$features) { my @values=grep { defined($_) && $_ ne '' } map { $_->{$column} } @$rows; $missing{$column}=scalar(@$rows)-scalar(@values); if(@values){$constant{$column}=1 if min(@values)==max(@values);} }
 for my $row (@$rows) { my $state=defined($row->{state_label})?$row->{state_label}:'MISSING'; my $event=defined($row->{event_target})?$row->{event_target}:'MISSING'; my $outcome=defined($row->{outcome_target})?$row->{outcome_target}:'MISSING'; $counts{state}{$state}++;$counts{event}{$event}++;$counts{outcome}{$outcome}++; }
 return {row_count=>scalar(@$rows),feature_count=>scalar(@$features),missing=>\%missing,constant=>[sort keys %constant],class_counts=>\%counts,causal_contract=>'Features and state use t or earlier; targets may use t+1..t+horizon.'};
}
sub print_report { my ($self,$d)=@_; print "SEQUENTIAL DATASET AUDIT\nRows: $d->{row_count}\nFeatures: $d->{feature_count}\nConstant: ",(@{$d->{constant}}?join(', ',@{$d->{constant}}):'none'),"\n"; for my $kind(qw(state event outcome)){print uc($kind),": ",join(', ',map{"$_=$d->{class_counts}{$kind}{$_}"}sort keys %{$d->{class_counts}{$kind}}),"\n";} print "Causality: $d->{causal_contract}\n"; }
1;
