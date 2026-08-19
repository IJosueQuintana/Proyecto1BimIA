package Market::ML::FinalGhostIO;
use strict; use warnings; use Carp qw(croak); use File::Basename qw(dirname); use File::Path qw(make_path);

sub write_csv {
    my ($class,%args)=@_; my $file=$args{file}//croak "Falta file\n"; my $rows=$args{rows}//[];
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY'; return if !@$rows;
    my $cols=$args{columns}; $cols=[sort keys %{$rows->[0]}] if ref($cols) ne 'ARRAY';
    my $dir=dirname($file); make_path($dir) if $dir ne '.' && !-d $dir;
    open my $fh,'>:encoding(UTF-8)',$file or croak "No se puede escribir '$file': $!\n";
    print $fh join(',',map{_esc($_)}@$cols),"\n";
    for my $r (@$rows) { print $fh join(',',map{_esc($r->{$_})}@$cols),"\n"; }
    close $fh; return $file;
}

sub read_csv {
    my ($class,%args)=@_; my $file=$args{file}//croak "Falta file\n";
    open my $fh,'<:encoding(UTF-8)',$file or croak "No se puede leer '$file': $!\n";
    my $h=<$fh>; croak "CSV sin cabecera: $file\n" if !defined $h; chomp $h; $h=~s/\r$//; my @cols=_parse($h); my @rows;
    while(my $line=<$fh>){ chomp$line;$line=~s/\r$//;next if $line eq '';my @v=_parse($line);my%r;@r{@cols}=@v;push@rows,\%r; }
    close $fh; return \@rows;
}

sub _esc { my($v)=@_;$v='' if !defined$v;$v="$v";if($v=~/[",\r\n]/){$v=~s/"/""/g;return qq{"$v"};}return $v; }
sub _parse { my($s)=@_;my@o;my$f='';my$q=0;for(my$i=0;$i<length$s;$i++){my$c=substr($s,$i,1);if($q){if($c eq '"'){if($i+1<length($s)&&substr($s,$i+1,1) eq '"'){$f.='"';$i++;}else{$q=0;}}else{$f.=$c;}}else{if($c eq '"'){$q=1;}elsif($c eq ','){push@o,$f;$f='';}else{$f.=$c;}}}push@o,$f;return@o;}
1;
