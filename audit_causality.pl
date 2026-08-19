use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";

use File::Basename qw(basename);
use Market::ML::CausalityAuditor;

my @files = @ARGV;
@files = (
    "$FindBin::Bin/datasets/ml_pipeline/train_trainable.csv",
    "$FindBin::Bin/datasets/ml_pipeline/validation_trainable.csv",
    "$FindBin::Bin/datasets/ml_pipeline/test_trainable.csv",
) if !@files;

my $auditor = Market::ML::CausalityAuditor->new(
    strict       => 1,
    max_examples => 25,
);

my $failed = 0;

for my $file (@files) {
    if (!-f $file) {
        warn "No existe '$file'. Ejecute primero perl ml_pipeline.pl o indique otro CSV.\n";
        $failed = 1;
        next;
    }

    my ($columns, $rows) = read_csv($file);
    my $report = $auditor->audit_rows(
        name    => basename($file),
        rows    => $rows,
        columns => $columns,
    );
    $auditor->print_report($report);
    $failed = 1 if !$report->{valid};
}

if ($failed) {
    die "\nLa auditoría causal encontró errores o archivos faltantes.\n";
}

print "\nTodos los datasets revisados aprobaron la auditoría causal.\n";
exit 0;

sub read_csv {
    my ($file) = @_;

    open my $fh, '<:encoding(UTF-8)', $file
        or die "No se puede abrir '$file': $!\n";

    my $header = <$fh>;
    die "CSV vacío: '$file'\n" if !defined $header;
    chomp $header;
    $header =~ s/\r$//;
    my @columns = parse_csv_line($header);

    my @rows;
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r$//;
        next if $line =~ /^\s*$/;

        my @values = parse_csv_line($line);
        my %row;
        for my $i (0 .. $#columns) {
            $row{$columns[$i]} = defined($values[$i]) ? $values[$i] : '';
        }
        push @rows, \%row;
    }

    close $fh;
    return (\@columns, \@rows);
}

sub parse_csv_line {
    my ($line) = @_;
    my @fields;
    my $field = '';
    my $quoted = 0;

    for (my $i = 0; $i < length($line); $i++) {
        my $char = substr($line, $i, 1);

        if ($char eq '"') {
            if ($quoted && $i + 1 < length($line)
                && substr($line, $i + 1, 1) eq '"') {
                $field .= '"';
                $i++;
            } else {
                $quoted = !$quoted;
            }
        } elsif ($char eq ',' && !$quoted) {
            push @fields, $field;
            $field = '';
        } else {
            $field .= $char;
        }
    }

    push @fields, $field;
    return @fields;
}
