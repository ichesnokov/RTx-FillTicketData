Set(@Plugins, qw(RT::Extension::AutofillCustomFields));
Set($AutofillCFSettings, {
    # Идентификатор "ключевого" поля - значение которого будет подставляться
    # в запрос вместо $key_field_value.
    key_field_id => 1,

    # Базы данных
    databases => {
        users => {
            # dbi:DriverName:database_name
            # dbi:DriverName:database_name@hostname:port
            # dbi:DriverName:database=database_name;host=hostname;port=port
            dsn      => 'dbi:mysql:users',
            username => 'root',
            password => '',
        },
        ip => {
            dsn      => 'dbi:mysql:ip_addresses',
            username => 'root',
            password => '',
        },
    },

    # Источники данных для пользовательских полей
    field_source => {
        # IP-адреса (CF id == 2)
        # Для получения данных из БД требуется 3
        2 => {
            database => 'users',
            sql      => q{SELECT ip FROM ip_addresses WHERE account_number = $key_value},
        },
        # Телефон (CF id == 3)
        3 => {
            command => q{/bin/echo "hello $key_value"},
        },
        # Адрес (CF id == 4)
        4 => {
            database => 'users',
            sql => q{SELECT address FROM users_addresses WHERE user_id = $key_value},
        },
    },
});
