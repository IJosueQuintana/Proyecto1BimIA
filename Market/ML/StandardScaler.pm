package Market::ML::StandardScaler;

use strict;
use warnings;
use List::Util qw(sum);

sub new {
    my ($class, %args) = @_;
    return bless {
        feature_columns => $args{feature_columns},
        numeric         => {},
        categorical     => {},
        output_features => [],
        fitted          => 0,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    die "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    die "No se puede ajustar StandardScaler con cero filas\n" if !@$rows;

    my $features = $self->{feature_columns};
    die "feature_columns debe ser ARRAY y no puede estar vacío\n"
        if ref($features) ne 'ARRAY' || !@$features;

    $self->{numeric} = {};
    $self->{categorical} = {};
    $self->{output_features} = [];

    for my $feature (@$features) {
        my @defined = map { defined($_->{$feature}) ? "$_->{$feature}" : '' } @$rows;
        my $is_numeric = 1;
        for my $value (@defined) {
            next if $value eq '';
            if (!_is_number($value)) {
                $is_numeric = 0;
                last;
            }
        }

        if ($is_numeric) {
            my @values = map {
                defined($_->{$feature}) && $_->{$feature} ne '' && _is_number($_->{$feature})
                    ? 0 + $_->{$feature}
                    : 0
            } @$rows;
            my $mean = sum(@values) / @values;
            my $variance = sum(map { ($_ - $mean) ** 2 } @values) / @values;
            my $std = sqrt($variance);
            $std = 1 if $std < 1e-12;
            $self->{numeric}{$feature} = { mean => $mean, std => $std };
            push @{$self->{output_features}}, $feature;
        }
        else {
            my %seen;
            my @categories = sort grep { !$seen{$_}++ }
                map { defined($_->{$feature}) ? "$_->{$feature}" : '' } @$rows;
            $self->{categorical}{$feature} = \@categories;
            push @{$self->{output_features}}, map { $feature . '=' . $_ } @categories;
        }
    }

    $self->{fitted} = 1;
    return $self;
}

sub transform {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    die "StandardScaler todavía no fue ajustado\n" if !$self->{fitted};
    die "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';

    my @vectors;
    for my $row (@$rows) {
        my @vector;
        for my $feature (@{$self->{feature_columns}}) {
            if (exists $self->{numeric}{$feature}) {
                my $value = defined($row->{$feature}) && $row->{$feature} ne ''
                    && _is_number($row->{$feature}) ? 0 + $row->{$feature} : 0;
                my $stats = $self->{numeric}{$feature};
                push @vector, ($value - $stats->{mean}) / $stats->{std};
            }
            else {
                my $value = defined($row->{$feature}) ? "$row->{$feature}" : '';
                for my $category (@{$self->{categorical}{$feature} // []}) {
                    push @vector, $value eq $category ? 1 : 0;
                }
            }
        }
        push @vectors, \@vector;
    }
    return \@vectors;
}

sub fit_transform {
    my ($self, %args) = @_;
    $self->fit(%args);
    return $self->transform(%args);
}

sub output_features {
    my ($self) = @_;
    return [@{$self->{output_features}}];
}

sub numeric_feature_count { return scalar(keys %{$_[0]{numeric}}); }
sub categorical_feature_count { return scalar(keys %{$_[0]{categorical}}); }

sub _is_number {
    my ($value) = @_;
    return defined($value) && $value =~ /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/;
}

1;
