use strict;
use warnings;
use feature qw(switch);

package RTx::AutofillCustomFields;

our $VERSION = '0.01';

use DBI;
use Digest::MD5 qw(md5_hex);
use JSON;

RT->AddJavaScript('RTx-AutofillCustomFields.js');

my $old_md5_sum = ''; # avoid uninitialized warning

my $config;
sub read_config {
    my $config_file = shift;

    # Reading file
    local $/;
    open my $FH, '<', $config_file
        or die "Could not open file $config_file: $!";
    my $json_data = <$FH>;
    close $FH;

    my $md5_sum = md5_hex($json_data);
    if ($old_md5_sum eq $md5_sum) {
        $RT::Logger->warn("MD5 sum matches the old one ($md5_sum), leaving config alone");
        return $config;
    }
    $RT::Logger->warn('New plugin configuration detected, re-reading config');

    $config = JSON::from_json($json_data);
}

my %dbh_for;

# Re-initialize database connections
sub init_connections {
    undef %dbh_for;

    for my $db_id (keys %{ $config->{databases} }) {
        $dbh_for{$db_id} = _connect_db($config->{databases}->{$db_id});
    }
}

# Connect to a database using configuration from $db_config
sub _connect_db {
    my $db_config = shift;

    my $dsn = "dbi:$db_config->{type}:$db_config->{database}";
    for my $field (qw(host port)) {
        $dsn .= ";$field=$db_config->{$field}" if $db_config->{$field};
    }

    my %more_attrs;
    given ($db_config->{type}) {
        when ('mysql') {
            %more_attrs = ( mysql_enable_utf8 => 1 );
        }
        when ('Pg') {
            %more_attrs = ( pg_enable_utf8 => 1 );
        }
    }
    my $dbh = DBI->connect(
        $dsn,
        $db_config->{user},
        $db_config->{password},
        {
            RaiseError => 1,
            PrintError => 1,
            %more_attrs
        },
    );
    $dbh->do('SET NAMES utf8');
    return $dbh;
}

1;
