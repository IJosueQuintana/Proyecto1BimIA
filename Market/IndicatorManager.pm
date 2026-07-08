package Market::IndicatorManager;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    my $self = { indicators => {} };
    bless $self, $class;
    return $self;
}

sub register {
    my ($self, $name, $indicator) = @_;
    $self->{indicators}{$name} = $indicator;
}

sub update_last {
    my ($self, $market_data) = @_;
    for my $name (keys %{$self->{indicators}}) {
        $self->{indicators}{$name}->calculate_all($market_data);
    }
}

sub get {
    my ($self, $name) = @_;
    return $self->{indicators}{$name}->values();
}

sub slice_array {
    my ($self, $name, $start, $end) = @_;
    my $arr = $self->get($name);
    $start = 0 if $start < 0;
    $end = $#$arr if $end > $#$arr;
    return [] if $end < $start;
    return [ @$arr[$start .. $end] ];
}

sub reset_all {
    my ($self) = @_;
    $_->reset() for values %{$self->{indicators}};
}

sub update_until {
    my ($self, $market_data, $until_index) = @_;

    for my $name (keys %{$self->{indicators}}) {
        if ($self->{indicators}{$name}->can('calculate_until')) {
            $self->{indicators}{$name}->calculate_until($market_data, $until_index);
        } else {
            $self->{indicators}{$name}->calculate_all($market_data);
        }
    }
}
1;
