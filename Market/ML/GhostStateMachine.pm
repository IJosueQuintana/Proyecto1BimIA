package Market::ML::GhostStateMachine;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        min_confidence => defined($args{min_confidence}) ? $args{min_confidence} : 0.55,
        current_state  => 'IDLE',
        ghost_active   => 0,
    }, $class;
}

sub update {
    my ($self, %args) = @_;
    my $state = uc($args{state} // 'IDLE');
    my $event = uc($args{event} // 'NONE');
    my $outcome = uc($args{outcome} // 'NONE');
    my $confidence = defined($args{confidence}) ? 0 + $args{confidence} : 1;

    my $ghost = 0;
    my $reason = 'NONE';
    if ($confidence >= $self->{min_confidence}) {
        if ($state eq 'INTERACTION' && ($event eq 'GRAB' || $event eq 'SWEEP')) {
            $ghost = 1;
            $reason = $event;
        }
        elsif ($state eq 'EXPANSION' && ($outcome eq 'RUN_UP' || $outcome eq 'RUN_DOWN')) {
            $ghost = 1;
            $reason = $outcome;
        }
    }

    $self->{current_state} = $state;
    $self->{ghost_active} = $ghost;
    return {
        state        => $state,
        ghost_active => $ghost,
        reason       => $reason,
        confidence   => $confidence,
    };
}

sub reset {
    my ($self) = @_;
    $self->{current_state} = 'IDLE';
    $self->{ghost_active} = 0;
    return $self;
}

sub current_state { return $_[0]{current_state}; }
sub ghost_active  { return $_[0]{ghost_active}; }

1;
