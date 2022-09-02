# Shell-H3C-BYOD

Tested in Openwrt 22.03.0-rc6.

## dependence

    bash curl coreutils-base64

### Usage

1. Place `autoauth.sh` and `user.conf` in `\etc`
1. Edit the username and password in `user.conf`
1. Place `autoauth` in `/etc/init.d`
1. Grant executable privileges

    `chmod 500 /etc/init.d/autoauth`
    `chmod 500 /etc/autoauth.sh`
1. Run `/etc/init.d/autoauth start` to test if it works (There will be no output for normal operation, please check the system log to determine if it is normal.)
1. Run `/etc/init.d/autoauth enable` to enable autostart
