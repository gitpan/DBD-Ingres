#   $Id: Ingres.pm,v 1.11 1997/03/20 08:49:19 ht Exp $
#
#   Copyright (c) 1994,1995 Tim Bunce
#             (c) 1996 Henrik Tougaard
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

require 5.003;

{
    package DBD::Ingres;

    use DBI ();
    use DynaLoader ();
    @ISA = qw(DynaLoader);

    $VERSION = '0.05';
    my $Revision = substr(q$Revision: 1.11 $, 10);

    require_version DBI 0.73;

    bootstrap DBD::Ingres $VERSION;

    $err = 0;		# holds error code   for DBI::err
    $errstr = "";	# holds error string for DBI::errstr
    $drh = undef;	# holds driver handle once initialised

    sub driver{
        return $drh if $drh;
        my($class, $attr) = @_;

        unless ($ENV{'II_SYSTEM'}){
            warn("II_SYSTEM not set. Ingres will fail\n");
        }

        $class .= "::dr";

        # not a 'my' since we use it above to prevent multiple drivers

        $drh = DBI::_new_drh($class, {
            'Name' => 'Ingres',
            'Version' => $VERSION,
            'Err'    => \$DBD::Ingres::err,
            'Errstr' => \$DBD::Ingres::errstr,
            'Attribution' => 'Ingres DBD by Henrik Tougaard',
            });

        $drh;
    }

    1;
}


{   package DBD::Ingres::dr; # ====== DRIVER ======
    use strict;

    sub errstr {
        DBD::Ingres::errstr(@_);
    }

    sub connect {
        my($drh, $dbname, $user, $auth)= @_;

        # create a 'blank' dbh
        my $this = DBI::_new_dbh($drh, {
            'Name' => $dbname,
            'USER' => $user, 'CURRENT_USER' => $user,
            });

        # Connect to the database..
        DBD::Ingres::db::_login($this, $dbname, $user, $auth)
            or return undef;

        $this;
    }

}


{   package DBD::Ingres::db; # ====== DATABASE ======
    use strict;

    sub errstr {
        DBD::Ingres::errstr(@_);
    }

    sub  rows {
        DBD::Ingres::rows(@_);
    }
    
    sub do {
        my($dbh, $statement, $attribs, @params) = @_;
        Carp::carp "\$dbh->do() attribs unused\n" if $attribs;
	Carp::carp "\$dbh->do() params unused\n" if @params;
        DBD::Ingres::db::_do($dbh, $statement);
    }

    sub prepare {
        my($dbh, $statement, @attribs)= @_;

        # create a 'blank' dbh
        my $sth = DBI::_new_sth($dbh, {
            'Statement' => $statement,
            });

        DBD::Ingres::st::_prepare($sth, $statement, @attribs)
            or return undef;

        $sth;
    }

}


{   package DBD::Ingres::st; # ====== STATEMENT ======
    use strict;

    sub errstr {
        DBD::Ingres::errstr(@_);
    }

    sub rows {
        DBD::Ingres::rows(@_);
    }
}

1;

=head1 NAME

DBD::Ingres - Ingres access interface for Perl5

=head1 SYNOPSIS

    $dbh = DBI->connect($dbname, $user, $options, 'Ingres')
    $sth = $dbh->prepare($statement)
    $sth->execute
    @row = $sth->fetchrow
    $sth->finish
    $dbh->commit
    $dbh->rollback
    $dbh->disconnect
    and many more

=head1 DESCRIPTION

DBD::Ingres is an extension to Perl which allows access to Ingres
databases. It is built on top of the standard DBI extension an
implements the methods that DBI require.

This document describes the differences between the "generic" DBD and
DBD::Ingres.

=head2 Not implemented

=over 4

=item Binding

Binding is not implented is this version of DBD::Ingres. It is planned
for a future release - but does not have high priority. Any takers?

As there is no binding, there is no need for reexecution of statements -
not that anything in the code prevents it - to my knowledge :-)

=item OpenIngres new features

The new features of OpenIngres are not (yet) supported in DBD::Ingres.

This includes BLOBS, decimal datatype and spatial datatypes.

Support will be added when the need arises - if you need it you add it ;-)

=back

=head2 Extensions/Changes

=over 4

=item $dbh->do

This is implemented as a call to 'EXECUTE IMMEDIATE'. (The generic way
is through prepare, bind, execute).
This will probably change when binds are added.

=item $sth->TYPE

Returns an array of the "perl"-type of the return fields of a select
statement.

The types are represented as:

=over 4

=item 'i': integer

All integer types, ie. int1, int2 and int4.

=item 'f': float

The types float, float8 and money.

=item 's': string

All other supported types, ie. char, varchar, text, date etc.

=back

=item $sth->SqlLen

Returns an array containing the lengths of the fields in Ingres, eg. an
int2 will return 2, a varchar(7) 7 and so on.

=item $sth->SqlType

Returns an array containing the Ingres types of the fields. The types
are given as documented in the Ingres SQL Reference Manual.

=back

=head1 NOTES

I wonder if I have forgotten something? There is no authoritative DBI
documentation (other than the code); it is difficult to document the
differences from a non-existent document ;-}

=head1 SEE ALSO

The DBI documentation (at the end of DBI.pm).

=head1 AUTHORS

DBI/DBD was developed by Tim Bunce, <Tim.Bunce@ig.co.uk>, who also
developed the DBD::Oracle that is the closest we have to a generic DBD
implementation.

Henrik Tougaard, <ht@datani.dk> developed the DBD::Ingres extension.
=cut
