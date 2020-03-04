# Installation

## Agent setup

### OpenWRT

1. You need to install `sudo`:

```
opkg update
opkg install sudo
```

2. Copy `sudoers.d/zabbix-openwrt` to `/etc/sudoers.d/zabbix-reboot-required`

3. Copy `reboot-required.sh` to `/etc/zabbix_zabbix_agentd.d/bin/reboot-required.sh`

4. Copy `zabbix_agentd.conf.d/reboot-required.openwrt.conf` to `/etc/zabbix_zabbix_agentd.d/reboot-required.conf`

5. Restart the agent: `/etc/init.d/zabbix_agentd restart`

## Zabbix Server setup

1. Import the template `zabbix_template_reboot_required.xml`

2. Apply it to your hosts
