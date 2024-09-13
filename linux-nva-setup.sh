#!/bin/sh

# Check out this blog for details: https://github.com/fluffy-cakes/azure_egress_nat


# # enable ip forwarding
# sudo sed -i 's/#net\.ipv4\.ip_forward=1/net\.ipv4\.ip_forward=1/g' /etc/sysctl.conf


# # Install strongwan 

sudo apt-get update
# sudo apt-get install strongswan strongswan-pki libstrongswan-extra-plugins -y

# # Get MAC Addresses of interfaces and save them as variables to be used later in cloud-init.yaml


mac1=$(sudo ip a | grep ether | awk 'NR==1{print $2}')
mac2=$(sudo ip a | grep ether | awk 'NR==2{print $2}')
mac3=$(sudo ip a | grep ether | awk 'NR==3{print $2}')

# # Adding two route tables

# sudo su
# sudo echo "200 eth0-rt" >> /etc/iproute2/rt_tables
# sudo echo "201 eth1-rt" >> /etc/iproute2/rt_tables
# sudo echo "202 eth2-rt" >> /etc/iproute2/rt_tables

# Disabling cloud-init routes - https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/linux-vm-multiple-virtual-network-interfaces-configuration?tabs=1subnet%2Cubuntu


sudo cat <<EOF | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network:
   config: disabled
EOF


# Modify netplan config

cat <<EOF | sudo tee /etc/netplan/50-cloud-init.yaml
network:
    ethernets:
        eth0:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 100
            dhcp6: false
            match:
                driver: hv_netvsc
                macaddress: $mac1
            set-name: eth0
            routes:
             - to: 10.98.0.0/24
               via: 10.98.0.1
               metric: 200
               table: 200
             - to: 0.0.0.0/0
               via: 10.98.0.1
               table: 200
            routing-policy:
             - from: 10.98.0.4/32
               table: 200
             - to: 10.98.0.4/32
               table: 200
        eth1:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 200
            dhcp6: false
            match:
                driver: hv_netvsc
                macaddress: $mac2
            set-name: eth1
            routes:
             - to: 10.98.1.0/24
               via: 10.98.1.1
               metric: 200
               table: 201
             - to: 0.0.0.0/0
               via: 10.98.1.1
               table: 201
             - to: 10.97.0.0/16
               via: 10.98.1.1
               table: 201
             - to: 168.63.129.16/32
               via: 10.98.1.1
               table: 201
            routing-policy:
             - from: 10.98.1.4/32
               table: 201
             - to: 10.98.1.4/32
               table: 201
        eth2:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 300
            dhcp6: false
            match:
                driver: hv_netvsc
                macaddress: $mac3
            set-name: eth2
            routes:
             - to: 10.98.2.0/24
               via: 10.98.2.1
               metric: 200
               table: 202
             - to: 0.0.0.0/0
               via: 10.98.2.1
               table: 202
            routing-policy:
             - from: 10.98.2.4/32
               table: 202
             - to: 10.98.2.4/32
               table: 202

    version: 2
EOF

sudo netplan apply

# # install software to save iptables on reboot
# sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
# sudo iptables-save | sudo tee -a /etc/iptables/rules.v4


# # # add the routes (eth1 = private, eth0 = internet)

# sudo ip route add 10.97.0.0/16 via 10.98.1.1 dev eth1
# sudo ip route add 168.63.129.16 via 10.98.1.1 dev eth1 proto dhcp src 10.98.1.4

# EOF

# sudo netplan apply

# #force iptables and routing on boot
# echo '#!/bin/bash
# /sbin/iptables-restore < /etc/iptables/rules.v4
# sudo ip route add 10.97.0.0/16 via 10.98.1.1 dev eth1
# sudo ip route add 168.63.129.16 via 10.98.1.1 dev eth1 proto dhcp src 10.98.1.4
# ' | sudo tee -a /etc/rc.local && sudo chmod +x /etc/rc.local


########################
## NAT Configuration ###
#########################

# enable the routing for the spoke VNET

# sudo iptables -t nat -A POSTROUTING -o eth0 -s 10.97.0.0/16 -j MASQUERADE
# sudo iptables -t nat -A POSTROUTING -o eth0 -s 10.0.0.0/8 -j MASQUERADE
# sudo iptables -t nat -A POSTROUTING -o eth0 -s 172.16.0.0/12 -j MASQUERADE
# sudo iptables -t nat -A POSTROUTING -o eth0 -s 192.168.0.0/16 -j MASQUERADE

# sudo iptables -t nat -D POSTROUTING -o eth0 -s 10.97.0.0/16 -j MASQUERADE
# sudo iptables -t nat -D POSTROUTING -o eth0 -s 10.0.0.0/8 -j MASQUERADE
# sudo iptables -t nat -D POSTROUTING -o eth0 -s 172.16.0.0/12 -j MASQUERADE
# sudo iptables -t nat -D POSTROUTING -o eth0 -s 192.168.0.0/16 -j MASQUERADE

# sudo su
# sudo iptables-save > /etc/iptables/rules.v4


#########################
## IP SEC / VPN Config ##
#########################


# Configure the IPSEC File

# sudo nano /etc/ipsec.conf

# # Add the following lines to your file


# #########################
# ## Policy-Based Tunnel ##
# #########################

# cat <<EOF | sudo tee /etc/ipsec.conf
# config setup
#         charondebug="all"
#         uniqueids=yes
# conn tunnel21
#         type=tunnel
#         left=10.98.0.4
#         leftsubnet=10.97.0.0/16
#         right=<PeerVPNIP>
#         rightsubnet=10.0.0.0/16
#         keyexchange=ikev2
#         keyingtries=%forever
#         authby=psk
#         ike=aes256-sha256-modp1024!
#         esp=aes256-sha256!
#         keyingtries=%forever
#         auto=start
#         dpdaction=restart
#         dpddelay=45s
#         dpdtimeout=45s
#         ikelifetime=28800s
#         lifetime=27000s
#         lifebytes=102400000
# EOF

# # Edit PSK

# sudo nano /etc/ipsec.secrets

# # Example

# cat <<EOF | sudo tee -a /etc/ipsec.secrets
# 10.98.0.4 <PeerVPNIP> : PSK "changeme123"
# EOF

# # # Remove NAT for IPSEC traffic outbound 

# sudo iptables -t nat -I POSTROUTING 1 -m policy --pol ipsec --dir out -j ACCEPT
# sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/16 -d 10.97.0.0/16 -j MASQUERADE # This is not be needed unless you want to SNAT on-prem traffic
# sudo iptables -A FORWARD -s 10.0.0.0/16 -d 10.97.0.0/16 -j ACCEPT # Allow traffic - Not needed if using above config as iptables allow it by default


# # Restart the VPN for changes to take effect

# sudo ipsec restart


# # For a route-based tunnel - https://docs.strongswan.org/docs/5.9/features/routeBasedVpn.html and https://blog.sys4.de/routing-based-vpn-with-strongswan-de.html


# # Remove all IP Tables

# sudo iptables -F
# sudo iptables -X
# sudo iptables -t nat -F
# sudo iptables -t nat -X
# sudo iptables -t mangle -F
# sudo iptables -t mangle -X
# sudo iptables -P INPUT ACCEPT
# sudo iptables -P FORWARD ACCEPT
# sudo iptables -P OUTPUT ACCEPT



# # Configure the tunnel interface and VPN routes


# echo '#!/bin/bash
# /sbin/iptables-restore < /etc/iptables/rules.v4
# sudo ip route add 10.97.0.0/16 via 10.98.1.1 dev eth1
# sudo ip route add 168.63.129.16 via 10.98.1.1 dev eth1 proto dhcp src 10.98.1.4
# ' | sudo tee -a /etc/rc.local && sudo chmod +x /etc/rc.local


# # # Edit IP SEC config
# cat <<EOF | sudo tee /etc/ipsec.conf
# config setup
#         charondebug="all"
#         uniqueids=yes
# conn tunnel21
#         type=tunnel
#         left=10.98.0.4
#         #leftsubnet=10.97.0.0/16
#         leftsubnet=0.0.0.0/0
#         right=<PeerVPNIP>
#         #rightsubnet=10.0.0.0/16
#         rightsubnet=0.0.0.0/0
#         keyexchange=ikev2
#         keyingtries=%forever
#         authby=psk
#         ike=aes256-sha256-modp1024!
#         esp=aes256-sha256!
#         keyingtries=%forever
#         auto=start
#         dpdaction=restart
#         dpddelay=45s
#         dpdtimeout=45s
#         ikelifetime=28800s
#         lifetime=27000s
#         lifebytes=102400000
#         mark=12
# EOF

# # # Edit the PSK - Same as above in Policy-based


# # # In strongSwan the IKE daemon also takes care of the routing. Since we do want to control the routing ourselves 
# # #we have to disable this feature in the service. The option can be found in the main section of the charon configuation file 
# # # /etc/strongswan.d/charon.conf:

# # sudo nano /etc/strongswan.d/charon.conf

# # charon {
# #   install_routes = no # Look for this entry and modify it as shown here
# # }

# # or

# sudo sed -i 's/^ *# *install_routes = yes/install_routes = no/' /etc/strongswan.d/charon.conf

# # # Restart the VPN for changes to take effect

# sudo ipsec restart

sudo reboot

# # Allow traffic - Not needed if using above config as iptables allow it by default

# sudo iptables -A FORWARD -s 10.0.0.0/16 -d 10.97.0.0/16 -j ACCEPT


# # Good to keep in mind - For listing and deleting an specific iptable entry

# sudo iptables -t nat -v -L POSTROUTING -n --line-number
# sudo iptables -t nat -D POSTROUTING {number-here}
# sudo iptables -v -L FORWARD -n --line-number
# sudo iptables -D FORWARD {number-here}






