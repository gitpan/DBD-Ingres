#!/usr/local/bin/perl -sw
# $Id: Makefile.PL,v 1.9 1997/03/20 08:49:19 ht Exp $

require 5.003;

use ExtUtils::MakeMaker 5.38, qw(&WriteMakefile $Verbose);
use Getopt::Long;
use Config;
use strict;

# Some MakeMaker's forged some FileHandle methods
require FileHandle unless defined(&FileHandle::new);

# This DBI must be installed before we can build a DBD.
# For those not using Dynamic loading this means building a
# new static perl in the DBI directory by saying 'make perl'
# and then using _that_ perl to make this one.
use DBI 0.73;

my %opts = (
    NAME => 'DBD::Ingres',
    VERSION_FROM => 'Ingres.pm',
    dist  => { DIST_DEFAULT=> 'clean distcheck disttest ci tardist',
               PREOP => '$(MAKE) -f Makefile.old distdir',
	       COMPRESS => 'gzip', SUFFIX => 'gz', },
    LINKTYPE => 'dynamic',
    OPTIMIZE => '-g',
);

# Options, typically only used for debugging
$::opt_g = '';		# enable debugging (s/-O/-g/g)
$::opt_v = 0;		# be verbose

GetOptions('v!', 'g!') or die "Invalid arguments";

$::opt_g &&= '-g';	# convert to actual string
$Verbose ||= $::opt_v;

# --- Introduction

print "\n Configuring DBD::Ingres ...
>>>\tRemember to actually *READ* the README file!
   \tEspecially if you have any problems.

   \tTry also 'perl Makefile.PL -v'


";

# --- Where is Ingres installed...

unless ($ENV{II_SYSTEM}){
    die "\$II_SYSTEM not defined. No Ingres?\n";
}
my $II = $ENV{II_SYSTEM};

print "Using Ingres in $II\n";

my $libhome = "";
my $linkwith = "-L$II/ingres/lib -lingres";  # good (?) guess for 6.4
if (-f "$II/ingres/files/abflnk.opt") {
    # the option file should give us all the libraries we need
    open(ABFLNK, "$II/ingres/files/abflnk.opt")
        or die "Can't read the option file ".
               "'$II/ingres/files/abflnk.opt'\n";
    $linkwith = join(" ", <ABFLNK>);
    close ABFLNK;
    $linkwith =~ s/\n//g;
    $linkwith =~ s/\$II_SYSTEM/$II/g;
}
my $linkopt = "";

# --- Handle special cases ---

$opts{DEFINE} = '-Wall -pedantic -Wno-comment -Wtraditional'
    if $Config{cc} eq 'gcc';

$opts{DEFINE} .= '-Xa' if $Config{cc} eq 'clcc';	# CenterLine CC

warn "WARNING: Your GNU C compiler is very old. Please upgrade.\n"
    if ($Config{gccversion} and $Config{gccversion} =~ m/^(1|2\.[1-5])/);

# OpenVMS has specialities:
if ($Config{osname} eq 'VMS') {
    $opts{OPTIMIZE} = "/optimize/nowarning";
    $opts{CCCDLFLAGS}="/nowarning";
    $linkopt = "II_SYSTEM:[ingres.files]esql.opt/opt";
    $linkwith = "";
    $libhome = "";
}

# Solaris needs the elf-library
if ($Config{osname} eq 'solaris') {
    $linkwith .= " -lelf";
}

# HP-UX 9 cannot link a non-PIC object file into a shared library.
if ($Config{osname} eq 'hpux' and $Config{osvers} < 10) {
    print "Warning: forced to build static not dynamic on $Config{osname} $Config{osvers}\n";
    print "         See README for more information.\n";
    $opts{LINKTYPE} = 'static';
}

# log key platform information to help me help you quickly
print "System: perl$] @Config{qw(myuname)}\n",
      "Compiler: @Config{qw(cc optimize ccflags)}\n",
      "Linker:   ". find_bin('ld') ."\n",
      "Linking with $linkwith\n" if $Verbose;

print "\n";

$opts{LIBS} = [ "$libhome $linkwith" ];
$opts{INC} = "-I\$(INSTALLSITEARCH)/auto/DBI -I\$(INSTALLSITEARCH)/DBI";
$opts{dynamic_lib} = { OTHERLDFLAGS => " $linkwith \$(COMPOBJS)" };
$opts{OBJECT} = 'Ingres$(OBJ_EXT) dbdimp$(OBJ_EXT)';
$opts{depend} = { "dbdimp\$(OBJ_EXT)" => "dbdimp.c Ingres.h",
		  "Ingres\$(OBJ_EXT)" => "Ingres.h",
                };
$opts{clean} = { FILES => "dbdimp.c Ingres.h" };
$opts{macro} = { ESQLC => "esqlc", ESQLCOPT => "-o.h" };

WriteMakefile(%opts);

exit 0;

sub MY::post_initialize {
    my $self = shift;
    # Ensure Ingperl.pm and ingperl.pl are installed into top lib dir
    $self->{PM}->{'Ingperl.pm'} = '$(INST_LIB)/Ingperl.pm';
    $self->{PM}->{'ingperl.pl'} = '$(INST_LIB)/ingperl.pl';
    
    '';
}

sub MY::postamble {
'
dbdimp.c Ingres.h : dbdimp.sc Ingres.sh
	$(ESQLC) $(ESQLCOPT) dbdimp.sc 
';
}


sub find_bin{
	my $bin = shift;
	foreach(split(/:/, $ENV{PATH})){
		return "$_/$bin" if -x "$_/$bin";
	}
	return "<$bin not found>";
}

{	# If perl Makefile.PL *-g* then switch on debugging
    package MY; # SUPER needs package context, $self is not sufficient
    sub const_cccmd {
		my($self) = shift;
		local($_) = $self->SUPER::const_cccmd(@_);
		s/\s-O\d?\b/ -g/g if $::opt_g;
		$_;
    }
    sub dynamic_lib { # VMS only - I hope
	my ($self) = shift;
	local($_) = $self->SUPER::dynamic_lib(@_);
	s!perlshr_attr.opt/Option!perlshr_attr.opt/Option,$linkopt!;
	$_;
    };

}

__END__
