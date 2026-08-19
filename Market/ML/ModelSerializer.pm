package Market::ML::ModelSerializer;

use strict;
use warnings;
use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Storable qw(nstore retrieve);

sub save {
    my ($class, %args) = @_;
    my $file = $args{file};
    my $object = $args{object};
    croak "Debe indicar file\n" if !defined($file) || $file eq '';
    croak "Debe indicar object\n" if !defined $object;
    my $dir = dirname($file);
    make_path($dir) if $dir ne '.' && !-d $dir;
    nstore({
        format_version => 1,
        saved_at_epoch => time,
        class          => ref($object) || '',
        object         => $object,
        metadata       => $args{metadata} // {},
    }, $file);
    return $file;
}

sub load {
    my ($class, %args) = @_;
    my $file = $args{file};
    croak "Debe indicar file\n" if !defined($file) || $file eq '';
    croak "No existe '$file'\n" if !-f $file;
    my $payload = retrieve($file);
    croak "Formato de modelo inválido en '$file'\n"
        if ref($payload) ne 'HASH' || !exists $payload->{object};
    return wantarray ? ($payload->{object}, $payload->{metadata}) : $payload->{object};
}

1;
