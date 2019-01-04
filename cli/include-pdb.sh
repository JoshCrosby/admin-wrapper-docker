#!/bin/bash
# vim:set expandtab ts=4 sw=4 ai:

# globals
#DEBUG=1
export DIRNAME=$(dirname $0)
export DUMPDIR=/backup
export TIMESTAMP=$(date +%Y-%m-%d.%H-%M-%S)
export CLEANFILE="" # to cleanup

umask 022

init_backup() {
    if [ ! -d $DUMPDIR ]; then
        mkdir $DUMPDIR
    fi
}

######################### ######################### #########################
not_root() {
    USER=$(id -u -n)
    if [ "$USER" = "root" ]; then
        echo "Run as yourself or an account with reflex configured."
        exit 1
    fi
    export USER
}

# Send to Slack as well as screen
notify() {
    msg "$@"
    [ $DEBUG ] && return 0 # don't send to slack when debugging
    if [ -x $DIRNAME/edmsg ]; then
        $DIRNAME/edmsg -s Normal "$*"
    fi
}

# send to screen
msg() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") $@"
}

# cleanup files matching this pattern
clean_onexit() {
    export CLEANFILE="$1"
}

# do cleanup of files
cleanup() {
    if [ -n "$CLEANFILE" ]; then
        $DIRNAME/cleanup-tmp-files "$CLEANFILE"
    fi
}

asu() {
    target=$1 
    action=$2
    shift
    shift
    if [ "$target" != "" -a "$USER" != $target ]; then
        $action sudo -s -H -u jenkins "$@"
        return $?
    else
        $action "$@"
        return $?
    fi
}

do_cmd() {
    [ $DEBUG ] && echo ">>> $@"
    "$@"
    return $?
}

do_cmd_err() {
    errfile=$HOME/$cmd.err
    do_cmd "$@" >> $errfile 2>&1
    if [ $? -gt 0 ]; then
        cat $errfile
        rm -f $errfile
        exit 1
    fi
    rm -f $errfile
}

# exit with file cleanup
abort() {
    if [ -n "$*" ]; then
        msg "$@"
    fi
    cleanup
    exit 1
}

# setup the pgpass secret file for using psql and other commands w/password
setup_pgpass() {
    rm -f /home/.pgpass

    umask 066

    # inception-fu
    perl  <<END
      sub encode() {
        my \$val = \$ENV{\$_[0]};
        \$val =~ s/\\\\/\\\\\\\\/g;
        \$val =~ s/:/\\\\:/g;
        return \$val;
    }

    #my \$dbhost = &encode("DATABASE_HOST");
    #my \$dbuser = &encode("DATABASE_USERNAME");
    my \$dbpass = &encode("DATABASE_PASSWORD");
    #my \$dbname = &encode("DATABASE_NAME");

    open(OUT, ">\$ENV{'HOME'}/.pgpass") || die;
    print OUT "*:*:*:*:\${dbpass}\n";
    close(OUT);
END
}

# run sql as an inline command
do_sqlc() {
    export PGOPTIONS='--client-min-messages=warning'
    setup_pgpass

    if [ -z "$1" ] ; then
        sql="$(cat)"
    else
        sql="$1"
    fi

    [ $DEBUG ] && echo "psql>> $sql"

    # DATABASE_NAME is required.  To connect with no db name, use db `template1`
    do_cmd psql --pset pager=off -d $DATABASE_NAME -U $DATABASE_USERNAME -h $DATABASE_HOST -c "$sql"

    return $?
}

# run sql as a block of statements
do_sql() {
    export PGOPTIONS='--client-min-messages=warning'
    setup_pgpass

    if [ -z "$1" ] ; then
        sql="$(cat)"
    else
        sql="$1"
    fi

    [ $DEBUG ] && echo "psql>> $sql"
    do_cmd psql -X -q -1 -v ON_ERROR_STOP=1 --pset pager=off -d $DATABASE_NAME -U $DATABASE_USERNAME -f - -h $DATABASE_HOST <<END
$sql
END
    status=$?

    if [ $status -gt 0 ]; then
        msg "operation failed: $sql"
    fi
    return $status
}

# generate a random db-safe password, skipping bad characters
# sorry for the script inception of perl in bash, this is easier this way (-BJG)
generate_pass() {
    perl  <<END
        my \$x=32;
        while (\$x >0) {
            my \$i = int(rand(93))+33;
            grep(/\$i/, (33, 34, 39, 92, 47, 64, 96)) && next;
            \$x--;
            print chr(\$i);
        }
END
}

# Update an admin user
update_pwreset() {
    local db=$1
    local user=$2
    local days=$3

    pass=$(generate_pass)
    expires=$(date  -d "+$days days" "+%Y-%m-%d")

    if [ -z "$expires" ]; then
        abort "Invalid expiration, cannot continue."
    fi

    do_sql "ALTER USER $user ENCRYPTED PASSWORD '$pass' VALID UNTIL '$expires';" || abort

    echo ".. Updated username: $user"
    echo ".. Updated password: $pass"
    echo ".. Expires on:       $expires"
}

update_admin() {
    local db=$1
    local user=$2

    drop_user $db $user

    msg "Creating ADMIN user $user"
    pass=$(generate_pass)
    expires=$(date  -d "+90 days" "+%Y-%m-%d")

    if [ -z "$expires" ]; then
        abort "Invalid expiration, cannot continue."
    fi

    do_sql "CREATE USER $user WITH CREATEDB PASSWORD '$pass' VALID UNTIL '$expires';"
    do_sql "GRANT ALL ON DATABASE $db TO $user;"
    do_sql "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $user;"
    do_sql "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $user;"

    echo ".. Username:   $user"
    echo ".. Password:   $pass"
    echo ".. Expires on: $expires"
}

update_readonly() {
    local db=$1
    local user=$2
    local age=$3

    drop_user $db $user

    msg "Creating READONLY user $user"

    if [ "$age" = "infinity" ]; then
        expires=infinity
    else
        expires=$(date  -d "+90 days" "+%Y-%m-%d")
    fi

    pass=$(generate_pass)
    do_sql "CREATE USER $user NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN PASSWORD '$pass' VALID UNTIL '$expires';"
    do_sql "GRANT CONNECT, TEMPORARY ON DATABASE $db TO $user;"

    # maybe we should enumerate each table, excluding certain ones
    do_sql "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO $user;"
    do_sql "GRANT SELECT ON ALL TABLES IN SCHEMA public TO $user;"

    echo ".. Username:   $user"
    echo ".. Password:   $pass"
    echo ".. Expires on: $expires"
}

drop_user() {
    local db=$1
    local user=$2

    msg "Dropping user $user"
    do_sql "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM $user;"
    do_sql "REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM $user;"
    do_sql "REVOKE ALL ON DATABASE $db FROM $user;"
    do_sql "DROP USER $user;"

}

# Load a service environment's settings w/reflex
load_reflex_dbenv() {
    local env=$1

    environ=$(launch env $env |grep '^export DATABASE_' 2>debug.out)
    if [ $? -gt 0 ]; then
        err=$(cat debug.out)
        abort $err
    fi
    eval "$environ"
    if [ -z "$DATABASE_URL" ]; then
        [ $DEBUG ] && cat debug.out
        abort "Failed to load environ (missing DATABASE_URL), do you have reflex setup properly?"
    fi

    # redundant, but good to know what we are setting
    export DATABASE_HOST
    export DATABASE_NAME
    export DATABASE_URL
    export DATABASE_USERNAME
    export DATABASE_PASSWORD
}
unset_reflex_dbenv() {
    unset DATABASE_HOST DATABASE_NAME DATABASE_URL DATABASE_USERNAME DATABASE_PASSWORD
}

# Load the lane for a service environment
load_svc_lane() {
    local env=$1

    LANE=$(engine svc get "$env" lane --format=txt)
    if [ $? -gt 0 ]; then
        abort "Unknown source service $env"
    fi
    export LANE
}

# If this env is prod, ask that it is okay
prod_dst_okay() {
    local env=$1
    load_svc_lane "$env"
    if [ "$LANE" = "prd" ]; then
        echo -n "Do you really want to clone into prod? [no] "
        # figure out what to do w/no TTY
        read answer
        if [ "$answer" != "YES" ]; then
            echo "Ok. If you do, you must type 'YES'"
            exit 1
        fi
        echo "Well, your loss.  Continuing in 5 seconds..."
        sleep 5
    fi
}

# Load the ops-db-bkup environment
load_reflex_opsenv() {
    eval $(launch env ops-db-bkup 2>/dev/null)
    # environs can set these
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

    if [ -z "$ENCKEY" ]; then
        abort "Failed to load environ, are you with reflex setup properly?"
    fi
    export ENCKEY=$ENCKEY
    export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    export AWS_BUCKET=$AWS_BUCKET
}

# call a deploy hook
call_svc_hook() {
    local env=$1
    local hook=$2
    local action=$3
    local label=$4

    if [ -n "$hook" ]; then
        notify -c platform-team "DB Restore $label service $env"
        output=$(curl --fail -v "${hook}-$action" 2>&1)
        if [ $? -gt 0 ]; then
            abort "Unable to call service hook=${hook}-$action

$output"
        fi
    else
        msg "Skipping $label $env as part of DB restore!  no $env.deploy-hook set"
    fi
}

# sub-backup backup so we can optionally call it without loading reflex env
_backup() {
    local env=$1
    local file=$2

    setup_pgpass

    msg "Backing up $env"
    start=$(date +%s)
    pgargs="-d $DATABASE_NAME -U $DATABASE_USERNAME -h $DATABASE_HOST"
    # -x is for stripping user grants; alternative is to pg_dumpall --globals-only and also restore it -BJG
    do_cmd pg_dump -x --clean -Z 9 --if-exists -Fc $pgargs -f $file || abort
    end=$(date +%s)
    finished=$(perl -e 'printf("Finished @ %0.2f Mb in %s seconds\n", (stat("'$file'"))[7]/1024/1024, ('$end'-'$start'))')
    msg "$finished"
}

# run a backup
backup() {
    local env=$1
    local file=$2

    load_reflex_dbenv $env

    _backup "$env" "$file"

    unset_reflex_dbenv
}

# run a database restore
restore() {
    local env=$1
    local file=$2

    load_reflex_dbenv $env
    setup_pgpass

    msg "Reset $env DB before restore"

    dbname=$DATABASE_NAME
    export DATABASE_NAME=template1
    do_sqlc "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$dbname';"
    do_sqlc "drop database $dbname;"
    do_sqlc "create database $dbname;"
    export DATABASE_NAME=$dbname
    do_sql "create extension citext;"

    msg "Starting restore to $env"
    do_cmd pg_restore -n public --clean --if-exists -1 -d $DATABASE_NAME -U $DATABASE_USERNAME -h $DATABASE_HOST $file || abort "unable to restore"

    unset_reflex_dbenv
}

# encrypt a backup file
encrypt() {
    local file=$1

    # assume: load_reflex_opsenv has been run
    msg "Encrypting backup"

    # assume: dumpfile is compressed from pg_dump
    do_cmd gpg --yes --batch --passphrase="$ENCKEY" --cipher-algo AES256 -c $file
    return $?
}

# push a file to s3
s3_archive() {
    local file=$1
    local prefix=$2
    msg "Pushing backup to S3"

    # assume: load_reflex_opsenv has been run
    s3cmd="s3cmd --access_key=$AWS_ACCESS_KEY_ID --secret_key=$AWS_SECRET_ACCESS_KEY"
    do_cmd $s3cmd put $file.gpg s3://$AWS_BUCKET/$prefix/ &&
      do_cmd $s3cmd put $file.gpg s3://$AWS_BUCKET/$prefix/
}

if [ -f /app/.build_version ]; then
    echo "... container build v$(cat /app/.build_version)"
fi
