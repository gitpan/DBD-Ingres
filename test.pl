use DBI qw(:sql_types);
$verbose = 0;
$testtable = "testhththt";

$dbname = $ENV{DBI_DBNAME} || $ENV{DBI_DSN} ||
           &ask_user("Please enter database-name: ");
$dbname = "dbi:Ingres:$dbname" unless $dbname =~ /^dbi:Ingres/;

print "1..26\n";

print "Testing: DBI->connect('$dbname'): "
 	if $verbose;
( $dbh = DBI->connect($dbname) )
    and print("ok 1\n") 
    or die "not ok 1: $DBI::errstr\n";

print "Testing: \$dbh->disconnect(): "
	if $verbose;
( $dbh->disconnect )
    and print( "ok 2\n" )
    or print "not ok 2: $DBI::errstr\n";

print "Re-testing: \$drh->connect('$dbname'): "
	if $verbose;
( $dbh = DBI->connect($dbname) )
    and print( "ok 3\n" )
    or print "not ok 3: $DBI::errstr\n";

print "Testing: \$dbh->do( 'CREATE TABLE $testtable
                       (
                        id INTEGER4,
                        name CHAR(64)
                       )' ): "
	if $verbose;
( $dbh->do( "CREATE TABLE $testtable ( id INTEGER4, name CHAR(64) )" ) )
    and print( "ok 4\n" )
    or print "not ok 4: $DBI::errstr\n";

print "Testing: \$dbh->do( 'DROP TABLE $testtable' ): "
	if $verbose;
( $dbh->do( "DROP TABLE $testtable" ) )
    and print( "ok 5\n" )
    or print "not ok 5: $DBI::errstr\n";

print "Re-testing: \$dbh->do( 'CREATE TABLE $testtable
                       (
                        id INTEGER4,
                        name CHAR(64)
                       )' ): "
	if $verbose;
( $dbh->do( "CREATE TABLE $testtable ( id INTEGER4, name CHAR(64) )" ) )
    and print( "ok 6\n" )
    or print "not ok 6: $DBI::errstr\n";

print "Testing: \$dbh->do( 'INSERT INTO $testtable VALUES ( 1, 'Alligator Descartes' )' ): "
	if $verbose;
( $dbh->do( "INSERT INTO $testtable VALUES( 1, 'Alligator Descartes' )" ) )
    and print( "ok 7\n" )
    or print "not ok 7: $DBI::errstr\n";

print "Testing: \$dbh->do( 'DELETE FROM $testtable WHERE id = 1' ): "
	if $verbose;
( $dbh->do( "DELETE FROM $testtable WHERE id = 1" ) )
    and print( "ok 8\n" )
    or print "not ok 8: $DBI::errstr\n";

print "Testing: \$cursor = \$dbh->prepare( 'SELECT FROM $testtable WHERE id = 1' ): "
	if $verbose;
( $cursor = $dbh->prepare( "SELECT * FROM $testtable WHERE id = 1" ) )
    and print( "ok 9\n" )
    or print( "not ok 9: $DBI::errstr\n" );

print "Testing: \$cursor->execute: "
	if $verbose;
( $cursor->execute )
    and print( "ok 10\n" )
    or print( "not ok 10: $DBI::errstr\n" );

print "*** Expect this test to fail with NO error message! (prints ok)\n"
	if $verbose;
print "Testing: \$cursor->fetchrow: "
	if $verbose;
( @row = $cursor->fetchrow ) 
    and print( "not ok 11: $row: '", join("', '", @row), "'\n" )
    or print( "ok  11 errstr:'$DBI::errstr'\n" );

print "Testing: \$cursor->finish: "
	if $verbose;
( $cursor->finish )
    and print( "ok 12\n" )
    or print( "not ok 12: $DBI::errstr\n" );
undef $cursor;

print "Testing placeholders and binding: "
	if $verbose;
( $sth = $dbh->prepare( "INSERT INTO $testtable(id, name) VALUES(?, ?)" ) )
    and print( "ok 13\n" )
    or print "not ok 13: $DBI::errstr\n";
( $sth->bind_param(1, 1, {TYPE => SQL_INTEGER}) )
    and print("ok 14\n")
    or print("not ok 14: $DBI:errstr\n");
( $sth->bind_param(2, "Aligator Descartes", {TYPE => SQL_CHAR}) )
    and print("ok 15\n")
    or print("not ok 15: $DBI:errstr\n");
( $sth->execute )
    and print( "ok 16\n" )
    or print "not ok 16: $DBI::errstr\n";

print "Re-testing bind:"
	if $verbose;
( $sth->execute( 2, 'Henrik Tougaard') )
    and print( "ok 17\n" )
    or print "not ok 17: $DBI::errstr\n";

print "Re-testing: \$cursor = \$dbh->prepare( 'SELECT FROM $testtable WHERE id = 1' ): "
	if $verbose;
( $cursor = $dbh->prepare( "SELECT * FROM $testtable WHERE id = 1" ) )
    and print( "ok 18\n" )
    or print "not ok 18: $DBI::errstr\n";

print "Types etc"
	if $verbose;
print "  Names: '", join("', '", @{$cursor->{'NAME'}}), "'\n",
      "  Nullabilty: '", join("', '", @{$cursor->{'NULLABLE'}}), "'\n",
      "  Type: '", join("', '", @{$cursor->{'TYPE'}}), "'\n",
      "  SqlLen: '", join("', '", @{$cursor->{'SqlLen'}}), "'\n",
      "  SqlType: '", join("', '", @{$cursor->{'SqlType'}}),
      "'\n"
	if $verbose;
      
print "Re-testing: \$cursor->execute: "
	if $verbose;
( $cursor->execute )
    and print( "ok 19\n" )
    or print "not ok 19: $DBI::errstr\n";

print "Re-testing: \$cursor->fetchrow: "
	if $verbose;
( @row = $cursor->fetchrow ) 
    and print( "ok 20\n" )
    or print "not ok 20: $DBI::errstr\n";

print "Re-testing: \$cursor->finish: "
	if $verbose;
( $cursor->finish )
    and print( "ok 21\n" )
    or print "not ok 21: $DBI::errstr\n";

print "Testing: \$dbh->do( 'UPDATE $testtable SET id = 3 WHERE name = 'Alligator Descartes'' ): "
	if $verbose;
( $dbh->do( "UPDATE $testtable SET id = 3 WHERE name = 'Alligator Descartes'" ) )
    and print( "ok 22\n" )
    or print "not ok 22: $DBI::errstr\n";

print "Testing update of all rows\n"
	if $verbose;
( $numrows = $dbh->do( "UPDATE $testtable SET id = id+1" ) )
    and print( "ok 23\n" )
    or print "not ok 23: $DBI::errstr\n";
# row-count!!!!
print "Affected rows = $DBI::rows, do returned: $numrows, should be 2\n"
	if $verbose;
print "not " if ($DBI::rows != 2 || $numrows != 2);
print "ok 24\n";


print "Re-testing: \$dbh->do( 'DROP TABLE $testtable' ): "
	if $verbose;
( $dbh->do( "DROP TABLE $testtable" ) )
    and print( "ok 25\n" )
    or print "not ok 25: $DBI::errstr\n";

print "Rolling back\n"
	if $verbose;
( $dbh->rollback )
   and print "ok 26\n"
   or print "not ok 26: $DBI::errstr\n";
print "*** Testing of DBD::Ingres complete! You appear to be normal! ***\n"
	if $verbose;

sub ask_user {
    # gets information from the user
    my $ans;
    print @_;
    $ans = <>;
    $ans;
}
