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
sub config { return $config; }

sub read_config {
    my $config_file = shift;

    my $json_data = read_file($config_file);
    my $md5_sum = md5_hex($json_data);
    if ($md5_sum eq $old_md5_sum) {
        $RT::Logger->warn("MD5 sum matches the old one ($md5_sum), leaving config alone");
        return $config;
    }

    $RT::Logger->warn('New plugin configuration detected, re-reading config',
        "old_sum: $old_md5_sum, new sum: $md5_sum");
    $old_md5_sum = $md5_sum;
    $config = from_json($json_data);
}

sub read_file {
    my $filename = shift;
    local $/;
    open my $FH, '<', $filename
        or die "Could not open file $filename: $!";
    return <$FH>;
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
        $db_config->{username},
        $db_config->{password},
        {
            RaiseError => 1,
            PrintError => 1,
            %more_attrs
        },
    );
    $dbh->do('SET NAMES utf8') if $db_config->{type} ne 'SQLite';
    return $dbh;
}

1;
