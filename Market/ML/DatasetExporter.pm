package Market::ML::DatasetExporter;

use strict;
use warnings;

use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(make_path);

sub new {
    my ($class, %args) = @_;

    return bless {
        eol => $args{eol} // "\n",
    }, $class;
}

sub export_csv {
    my ($self, %args) = @_;

    my $file =
        $args{file};

    my $rows =
        $args{rows}
        // [];

    my $columns =
        $args{columns}
        // [];

    croak "Debe indicar file\n"
        if !defined $file || $file eq '';

    croak "rows debe ser ARRAY\n"
        if ref($rows) ne 'ARRAY';

    croak "columns debe ser ARRAY\n"
        if ref($columns) ne 'ARRAY' || !@$columns;

    my $directory =
        dirname($file);

    make_path($directory)
        if $directory ne '.'
        && !-d $directory;

    open my $fh, '>:encoding(UTF-8)', $file
        or croak "No se puede escribir '$file': $!\n";

    # Encabezado
    print {$fh}
        join(
            ',',
            map {
                _csv_escape($_)
            } @$columns
        ),
        $self->{eol};

    # Filas
    for my $row (@$rows) {

        next if ref($row) ne 'HASH';

        print {$fh}
            join(
                ',',
                map {
                    _csv_escape(
                        defined $row->{$_}
                            ? $row->{$_}
                            : ''
                    )
                } @$columns
            ),
            $self->{eol};
    }

    close $fh
        or croak "No se pudo cerrar '$file': $!\n";

    return scalar @$rows;
}

sub _csv_escape {
    my ($value) = @_;

    $value = ''
        if !defined $value;

    $value = "$value";

    if ($value =~ /[",\r\n]/) {

        $value =~ s/"/""/g;

        return qq{"$value"};
    }

    return $value;
}
sub filter_trainable_rows {
    my ($self, %args) = @_;

    my $rows =
        $args{rows}
        // [];

    die "rows debe ser una referencia ARRAY\n"
        if ref($rows) ne 'ARRAY';

    my @filtered;

    for my $row (@$rows) {

        next if ref($row) ne 'HASH';

        my $target =
            uc(
                $row->{target}
                // 'NONE'
            );

        my $structure =
            uc(
                $row->{structure_type}
                // 'UNKNOWN'
            );

        my $atr =
            defined $row->{atr_14}
            ? 0 + $row->{atr_14}
            : 0;

        my $pivot_index =
            $row->{pivot_index};

        my $confirmation_index =
            $row->{confirmation_index};

        # Solo eventos ya clasificados.
        next
            if $target ne 'RUN'
            &&
            $target ne 'GRAB'
            &&
            $target ne 'SWEEP';

        # El ATR debe estar disponible.
        next
            if $atr <= 0;

        # Excluye los primeros pivotes H y L sin clasificación
        # estructural completa.
        next
            if $structure ne 'HH'
            &&
            $structure ne 'HL'
            &&
            $structure ne 'LH'
            &&
            $structure ne 'LL';

        # Los índices deben existir.
        next
            if !defined $pivot_index
            ||
            !defined $confirmation_index;

        # Nunca se permite confirmación previa al pivote.
        next
            if $confirmation_index < $pivot_index;

        push @filtered, $row;
    }

    return \@filtered;
}
1;