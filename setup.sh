#!/bin/bash

echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config

yum install httpd php git -y
git clone  https://github.com/vyshnavlal/aws-elb-site-1
cp -r /var/website/* /var/www/html/
chown -R apache:apache /var/www/html/*

systemctl restart httpd.service
systemctl enable httpd.service
