#   $Id: Ingres.pm,v 1.4 1996/12/18 10:44:33 ht Exp $
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

    $VERSION = '0.0201';
    my $Revision = substr(q$Revision: 1.4 $, 10);

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

    sub  rows {
        DBD::Ingres::rows(@_);
    }
}

1;
