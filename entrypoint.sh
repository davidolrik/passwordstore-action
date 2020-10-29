#!/bin/sh

# Go home
cd ~

# Import private key
echo "* Importing private key"
echo "${INPUT_PRIVATE_KEY}" | gpg --import --batch --yes --passphrase "${INPUT_PASSPHRASE}"
PRIVATE_KEY_ID=$(gpg --list-secret-keys --with-colons | grep fpr | awk -F: '{print $10}' | head -1)

echo "* Trust imported keys"
for key_id in `gpg --list-secret-keys --with-colons | grep fpr | awk -F: '{print $10}'`; do
    echo -e "5\ny\n" | gpg --no-tty --command-fd 0 --edit-key "$key_id" trust save quit
done

echo "* List keys"
gpg --list-keys --batch --no-tty --keyid-format long

echo "* List secret keys"
gpg --list-secret-keys --batch --no-tty --keyid-format long

# Clone password-store repo into home-directory
export PASSWORD_STORE_DIR="${GITHUB_WORKSPACE}/${INPUT_REPOSITORY}"
export PASSWORD_STORE_GPG_OPTS="-vv --pinentry-mode=loopback --batch --passphrase '${INPUT_PASSPHRASE}' -r '${PRIVATE_KEY_ID}'"

echo "* Looping over env"
for var_name in `perl -E 'foreach $k ( keys %ENV ) { say $k if $ENV{$k} =~ /^pass(?:\+multiline)?:\/\//; }'`; do
    echo "* Exporting $var_name"
    secret_path=$(printenv $var_name | awk -F ':///?' '{print $2}')
    secret=$(pass $secret_path)

    # Escape percent signs and add a mask per line (see https://github.com/actions/runner/issues/161)
    escaped_mask_value=$(echo "$secret" | sed -e 's/%/%25/g')
    IFS=$'\n'
    for line in $escaped_mask_value; do
        echo "::add-mask::$line"
    done
    unset IFS

    if [ -n "${GITHUB_ENV}" ]; then
        # A random 64 character string is used as the heredoc identifier, to make it practically
        # impossible that this string appears in the secret.
        random_heredoc_identifier=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n1)

        echo "$var_name<<${random_heredoc_identifier}" >> $GITHUB_ENV
        echo "$secret" >> $GITHUB_ENV
        echo "${random_heredoc_identifier}" >> $GITHUB_ENV
    else
        # Escape percent signs and newlines when setting the environment variable
        escaped_env_var_value=$(echo -n "$secret" | sed -z -e 's/%/%25/g' -e 's/\n/%0A/g')
        echo "::set-env name=$var_name::$escaped_env_var_value"
    fi
done
