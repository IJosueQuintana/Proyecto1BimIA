package Market::ML::SequentialDatasetLoader;

use strict;
use warnings;
use Carp qw(croak);
use Market::ML::SequentialFeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        schema => $args{schema} // 'Market::ML::SequentialFeatureSchema',
    }, $class;
}

sub load_csv {
    my ($self, %args) = @_;
    my $file = $args{file};
    croak "Debe indicar file\n" if !defined($file) || $file eq '';
    open my $fh, '<:encoding(UTF-8)', $file
        or croak "No se puede leer '$file': $!\n";

    my $header = <$fh>;
    croak "El CSV '$file' está vacío\n" if !defined $header;
    chomp $header;
    $header =~ s/\r$//;
    my @columns = _parse_csv_line($header);
    croak "El CSV '$file' no tiene columnas\n" if !@columns;

    my %present = map { $_ => 1 } @columns;
    for my $required (@{$self->{schema}->all_columns}) {
        croak "Falta la columna requerida '$required' en '$file'\n"
            if !$present{$required};
    }

    my @rows;
    my $line_number = 1;
    while (my $line = <$fh>) {
        $line_number++;
        chomp $line;
        $line =~ s/\r$//;
        next if $line =~ /^\s*$/;
        my @values = _parse_csv_line($line);
        croak "Cantidad de columnas inválida en '$file', línea $line_number\n"
            if @values != @columns;
        my %row;
        @row{@columns} = @values;
        push @rows, \%row;
    }
    close $fh;
    return \@rows;
}

sub split_by_source {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    my $train_files = $args{train_files} // [];
    my $validation_files = $args{validation_files} // [];
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    croak "train_files debe ser ARRAY\n" if ref($train_files) ne 'ARRAY';
    croak "validation_files debe ser ARRAY\n" if ref($validation_files) ne 'ARRAY';

    my %train = map { $_ => 1 } @$train_files;
    my %validation = map { $_ => 1 } @$validation_files;
    my (@train_rows, @validation_rows, @ignored_rows);

    for my $row (@$rows) {
        next if ref($row) ne 'HASH';
        my $source = $row->{source_file} // '';
        if ($train{$source}) {
            push @train_rows, $row;
        }
        elsif ($validation{$source}) {
            push @validation_rows, $row;
        }
        else {
            push @ignored_rows, $row;
        }
    }

    croak "TRAIN quedó vacío; revise los nombres de source_file\n" if !@train_rows;
    croak "VALIDATION quedó vacío; revise los nombres de source_file\n" if !@validation_rows;

    return {
        train_rows      => \@train_rows,
        validation_rows => \@validation_rows,
        ignored_rows    => \@ignored_rows,
    };
}

sub labels {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    my $column = $args{column} // 'state_label';
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    return [map { uc($_->{$column} // '') } @$rows];
}

sub sequence_ids {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    return [map {
        join('|', $_->{source_file} // '', $_->{symbol} // '', $_->{timeframe} // '')
    } @$rows];
}

sub feature_columns {
    my ($self) = @_;
    return $self->{schema}->feature_columns;
}

sub rows_for_supervised_model {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    my $target_column = $args{target_column} // 'state_label';
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    return [map {
        my %copy = %$_;
        $copy{target} = uc($_->{$target_column} // '');
        \%copy;
    } @$rows];
}

sub _parse_csv_line {
    my ($line) = @_;
    my @fields;
    my $field = '';
    my $quoted = 0;
    my @chars = split //, $line;
    for (my $i = 0; $i < @chars; $i++) {
        my $char = $chars[$i];
        if ($quoted) {
            if ($char eq '"') {
                if ($i + 1 < @chars && $chars[$i + 1] eq '"') {
                    $field .= '"';
                    $i++;
                } else {
                    $quoted = 0;
                }
            } else {
                $field .= $char;
            }
        } else {
            if ($char eq '"') {
                $quoted = 1;
            } elsif ($char eq ',') {
                push @fields, $field;
                $field = '';
            } else {
                $field .= $char;
            }
        }
    }
    croak "CSV con comillas sin cerrar\n" if $quoted;
    push @fields, $field;
    return @fields;
}

1;
